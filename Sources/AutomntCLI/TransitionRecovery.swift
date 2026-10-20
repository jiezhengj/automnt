#if canImport(AutomntCore)
import AutomntCore
#endif
import Foundation
import Dispatch

struct CLIRecoveryRequest: Equatable, Sendable {
    let transitionID: UUID
    let generation: UInt64

    /// Exact grammar; malformed recovery commands never reach installation/healing.
    static func parse(_ arguments: [String]) -> CLIRecoveryRequest? {
        guard arguments.count == 3, arguments[1] == "--generation",
              let id = UUID(uuidString: arguments[0]),
              id.uuidString.lowercased() == arguments[0].lowercased(),
              let generation = UInt64(arguments[2]), String(generation) == arguments[2] else { return nil }
        return CLIRecoveryRequest(transitionID: id, generation: generation)
    }
}

enum CLIRecoveryProblem: String, Error, Sendable {
    case transitionInProgress, operationInProgress, interrupted, requiresRepair, staleRequest, appOwner, notInterrupted
}

/// Holds neither lock across a system call; HandoffCoordinator owns handoff.lock
/// throughout recovery and this adapter revalidates the complete journal under it.
struct CLIRecoveryAdapter: HandoffServiceAdapter {
    let directory: URL
    let request: CLIRecoveryRequest
    let revision: ConfigRevision
    let underlying: any HandoffServiceAdapter

    func stopAndVerify(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        let journal = try validateCLIRecovery(directory: directory, request: request)
        guard journal.pending.revision == revision, owner == .cli else { throw CLIRecoveryProblem.staleRequest }
        guard try FileConfigRepository(authorizedDirectory: directory).read().revision == revision else {
            throw CLIRecoveryProblem.staleRequest
        }
        // A pending worker remains repair-required; never erase its intent or kill a PID.
        try verifyCLIRecoveryIdle(directory: directory)
        return try await underlying.stopAndVerify(owner: owner, deadline: deadline)
    }
    func register(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        throw CLIRecoveryProblem.requiresRepair
    }
    func status(owner: BackendState.Owner, deadline: ContinuousClock.Instant) async throws -> BackendState.ServiceStatus {
        try await underlying.status(owner: owner, deadline: deadline)
    }
    func requestEvaluation(state: BackendState, deadline: ContinuousClock.Instant) async throws {
        throw CLIRecoveryProblem.requiresRepair
    }
}

/// Must run before touching any service, including when a mixed journal lists CLI first.
func validateCLIRecovery(directory: URL, request: CLIRecoveryRequest) throws -> BackendTransitionJournal {
    let store = BackendStateStore(authorizedDirectory: directory)
    let journal = try store.interruptedJournal(id: request.transitionID)
    guard journal.pending.generation == request.generation else { throw CLIRecoveryProblem.staleRequest }
    for state in [journal.previous, journal.pending, journal.priorPending].compactMap({ $0 }) {
        guard state.owner != .app, state.desiredOwner != .app else { throw CLIRecoveryProblem.appOwner }
    }
    guard [journal.previous, journal.pending, journal.priorPending].compactMap({ $0 }).contains(where: {
        $0.owner == .cli || $0.desiredOwner == .cli
    }) else { throw CLIRecoveryProblem.requiresRepair }
    return journal
}

private func verifyCLIRecoveryIdle(directory: URL) throws {
    let lock = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock"))
    try withExtendedLifetime(lock) { try WorkerOperationStore(authorizedDirectory: directory).verifyIdle() }
}

/// Nonblocking probe distinguishes an active coordinator from abandoned durable intent.
/// No state/config initialization, purge, registration, or automatic repair.
func inspectCLIRecovery(directory: URL) throws -> (CLIRecoveryProblem, CLIRecoveryRequest?) {
    let handoff: StableFileLock
    do { handoff = try StableFileLock(url: directory.appendingPathComponent("handoff.lock")) }
    catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK) {
        return (.transitionInProgress, nil)
    }
    return try withExtendedLifetime(handoff) {
        let store = BackendStateStore(authorizedDirectory: directory)
        if let state = try? store.read(), state.phase == .active || state.phase == .stopped {
            return (.notInterrupted, nil)
        }
        let journal = try store.journal()
        let request = CLIRecoveryRequest(transitionID: journal.id, generation: journal.pending.generation)
        do { _ = try validateCLIRecovery(directory: directory, request: request) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK) {
            return (.operationInProgress, nil)
        }
        let evaluation: StableFileLock
        do { evaluation = try StableFileLock(url: directory.appendingPathComponent("evaluation.lock")) }
        catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EWOULDBLOCK) {
            return (.operationInProgress, nil)
        }
        do { try withExtendedLifetime(evaluation) { try WorkerOperationStore(authorizedDirectory: directory).verifyIdle() } }
        catch { return (.requiresRepair, nil) }
        return (journal.pending.phase == .failed ? .requiresRepair : .interrupted, request)
    }
}

func recoverCLITransition(directory: URL, request: CLIRecoveryRequest,
                          adapter: any HandoffServiceAdapter,
                          deadline: ContinuousClock.Instant) async throws -> BackendState {
    // Probe is advisory. The wrapper repeats validation after the coordinator owns
    // handoff.lock, so a replacement journal cannot cause services to be stopped.
    let (problem, observed) = try inspectCLIRecovery(directory: directory)
    guard problem == .interrupted || (problem == .requiresRepair && observed != nil) else { throw problem }
    guard observed == request else { throw CLIRecoveryProblem.staleRequest }
    let journal = try validateCLIRecovery(directory: directory, request: request)
    let revision = try FileConfigRepository(authorizedDirectory: directory).read().revision
    guard revision == journal.pending.revision else { throw CLIRecoveryProblem.staleRequest }
    let fenced = CLIRecoveryAdapter(directory: directory, request: request, revision: revision, underlying: adapter)
    return try await HandoffCoordinator(authorizedDirectory: directory).recoverInterruptedTransition(
        id: request.transitionID, adapter: fenced, deadline: deadline)
}

func cliRecoveryStatusLine() -> String {
    do {
        let (problem, request) = try inspectCLIRecovery(directory: CLIOwnership.directory)
        var line = "[cli-recovery:\(problem.rawValue)] " + cliRecoveryMessage(problem)
        if let request {
            line += "\n  automnt --recover-transition \(request.transitionID.uuidString) --generation \(request.generation)"
        }
        return line
    } catch {
        let problem = error as? CLIRecoveryProblem ?? .requiresRepair
        return "[cli-recovery:\(problem.rawValue)] " + cliRecoveryMessage(problem)
    }
}

func cliRecoveryMessage(_ problem: CLIRecoveryProblem) -> String {
    switch problem {
    case .transitionInProgress: return tr("后台转换仍在进行；稍后重试。", "A backend transition is still in progress; retry later.")
    case .operationInProgress: return tr("后台操作仍持有锁；稍后重试。", "A backend operation still holds the lock; retry later.")
    case .interrupted: return tr("后台转换已中断。可使用下列命令显式恢复到停用状态；不会自动启用服务。", "The backend transition was interrupted. Explicitly recover to stopped with the command below; it will not enable the service.")
    case .requiresRepair: return tr("后台需要修复；仅在下方提供恢复命令时可执行。未知系统状态或未完成的任务不会被清除。", "Backend repair is required. Run recovery only if a command is shown below. Unknown system state or pending workers will not be cleared.")
    case .staleRequest: return tr("转换身份、代次或配置已变化；重新查看 --status。", "Transition identity, generation or configuration changed; inspect --status again.")
    case .appOwner: return tr("转换涉及应用后台；请在应用内恢复，CLI 不会接管。", "The transition involves the app backend; recover in the app. The CLI will not take over.")
    case .notInterrupted: return tr("没有待恢复的中断转换。", "There is no interrupted transition to recover.")
    }
}

func runCLIRecoveryCommand(arguments: [String]) -> Int32 {
    guard let request = CLIRecoveryRequest.parse(arguments) else {
        fputs("Usage: automnt --recover-transition UUID --generation N\n", stderr)
        return 64
    }
    guard !DaemonRuntime.isDaemon() else { return 1 }
    let directory = CLIOwnership.directory
    let box = LockedBox<Result<BackendState, CLIRecoveryProblem>?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    let task = Task.detached {
        do {
            let revision = try FileConfigRepository(authorizedDirectory: directory).read().revision
            let state = try await recoverCLITransition(directory: directory, request: request,
                adapter: CLIServiceHandoffAdapter(revision: revision, strictIdentity: true),
                deadline: ContinuousClock.now.advanced(by: .seconds(30)))
            box.value = .success(state)
        } catch {
            box.value = .failure(error as? CLIRecoveryProblem ?? .requiresRepair)
        }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 35) == .success, let result = box.value else {
        task.cancel()
        fputs("[cli-recovery:requiresRepair] " + cliRecoveryMessage(.requiresRepair) + "\n", stderr)
        return 1
    }
    switch result {
    case .success:
        print(tr("✓ 后台已恢复到停用状态；配置与已挂载共享保留。需要重新启用时显式运行 --install。",
                 "✓ Backend recovered to stopped; configuration and mounted shares preserved. Run --install explicitly to enable it again."))
        return 0
    case .failure(let problem):
        fputs("[cli-recovery:\(problem.rawValue)] " + cliRecoveryMessage(problem) + "\n", stderr)
        return 1
    }
}
