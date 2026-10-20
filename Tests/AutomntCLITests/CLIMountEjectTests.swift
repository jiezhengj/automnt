import Foundation
import Testing
@testable import AutomntCLI
import AutomntCore

/// T077：CLI 单共享挂载与普通弹出入口。
///
/// 覆盖范围：参数解析、身份解析失败、未知目标、并发变更拒绝、弹出失败分类。
/// 明确不覆盖（需真实环境，报告中如实标注）：
/// - `CLIOwnership.beginEvaluation()` 之后的真实所有权转换与 NetFS/DA 内核动作；
/// - 真实 SMB 卷的挂载与普通弹出（需要可达的 SMB 服务器与已授权目录）。
@Suite(.serialized)
struct CLIMountEjectTests {

    /// `Result.failure` 不是标准属性；用匹配取出失败类别，保持断言简洁。
    private func parseFailure(_ arguments: [String], intent: CLISingleShareIntent) -> CLISingleShareParseProblem? {
        guard case .failure(let problem) = parseSingleShareTarget(arguments, intent: intent) else { return nil }
        return problem
    }

    // MARK: - 参数解析

    @Test func parsesCompleteSMBAddressIntoStableIdentity() throws {
        let result = parseSingleShareTarget(["smb://files.example/Docs"], intent: .mount)
        let request = try #require(try? result.get())
        #expect(request.intent == .mount)
        #expect(request.identity == "//files.example/docs")
        #expect(request.rawURL == "smb://files.example/Docs")
    }

    @Test func explicitPortBecomesPartOfIdentity() throws {
        let result = parseSingleShareTarget(["smb://files.example:1445/Docs"], intent: .eject)
        let request = try #require(try? result.get())
        #expect(request.intent == .eject)
        #expect(request.identity == "//files.example:1445/docs")
    }

    /// 同一目标的不同书写形式必须得到同一身份，否则目标定位会漏配。
    @Test func equivalentSpellingsShareOneIdentity() throws {
        let forms = [
            "smb://files.example/Docs",
            "smb://FILES.example/Docs",
            "smb://files.example:445/Docs",
            "smb://files.example/Docs/"
        ]
        let identities = try forms.map { form in
            try #require(try? parseSingleShareTarget([form], intent: .mount).get()).identity
        }
        #expect(Set(identities).count == 1)
    }

    @Test func rejectsMissingAndExtraArguments() {
        #expect(parseFailure([], intent: .mount) == .missingArgument)
        #expect(parseFailure([], intent: .eject) == .missingArgument)
        #expect(parseFailure(["smb://a.example/x", "smb://b.example/y"], intent: .mount) == .unexpectedExtraArgument)
    }

    @Test func rejectsNonSMBProtocols() {
        #expect(parseFailure(["https://files.example/Docs"], intent: .mount) == .notSMB)
        #expect(parseFailure(["afp://files.example/Docs"], intent: .mount) == .notSMB)
        // 完整地址是面向用户子命令的要求，不接受 `//host/share` 简写。
        #expect(parseFailure(["//files.example/Docs"], intent: .mount) == .notSMB)
        #expect(parseFailure(["not a url"], intent: .mount) == .notSMB)
    }

    /// 凭据绝不允许经 argv 进入本进程；用户名列、密码列与 `@` 一律拒绝。
    @Test func rejectsEmbeddedCredentials() {
        #expect(parseFailure(["smb://user:secret@files.example/Docs"], intent: .mount) == .embeddedCredentials)
        #expect(parseFailure(["smb://user@files.example/Docs"], intent: .mount) == .embeddedCredentials)
        #expect(parseFailure(["smb://files.example/Docs@x"], intent: .eject) == .embeddedCredentials)
    }

    @Test func rejectsMissingHostAndMissingShare() {
        #expect(parseFailure(["smb:///Docs"], intent: .mount) == .missingHost)
        #expect(parseFailure(["smb://files.example"], intent: .mount) == .missingShare)
        #expect(parseFailure(["smb://files.example/"], intent: .mount) == .missingShare)
    }

    @Test func rejectsOutOfRangePort() {
        #expect(parseFailure(["smb://files.example:0/Docs"], intent: .mount) == .invalidPort)
        #expect(parseFailure(["smb://files.example:99999/Docs"], intent: .mount) == .invalidPort)
    }

    /// 每个拒绝类别都有稳定标签，回归可断言且不含用户数据。
    @Test func everyParseProblemHasAStableTag() {
        let problems: [CLISingleShareParseProblem] = [.missingArgument, .unexpectedExtraArgument, .notSMB,
            .embeddedCredentials, .missingHost, .missingShare, .invalidPort, .unresolvableIdentity]
        #expect(Set(problems.map(\.tag)).count == problems.count)
        #expect(problems.allSatisfy { !$0.tag.isEmpty })
    }

    // MARK: - 目标定位

    private func configuration() -> AutomntConfig {
        AutomntConfig(hosts: [
            HostConfig(host: "files.example", shares: [
                SMBShareConfig(name: "Docs", smbURL: "smb://files.example/Docs",
                               mountPoint: "/Volumes/Docs")
            ]),
            HostConfig(host: "media.example", shares: [
                SMBShareConfig(name: "Docs", smbURL: "smb://media.example/Docs",
                               mountPoint: "/Volumes/Media-Docs")
            ])
        ])
    }

    @Test func locatesTheExactManagedTarget() throws {
        let target = locateSingleShareTarget(identity: "//media.example/docs", in: configuration())
        guard case .found(let host, let share, let hostIndex, let shareIndex) = target else {
            Issue.record("expected a located target")
            return
        }
        #expect(host.host == "media.example")
        #expect(share.mountPoint == "/Volumes/Media-Docs")
        #expect(hostIndex == 1)
        #expect(shareIndex == 0)
    }

    /// 同名的共享在不同服务器上是不同目标：身份必须精确，不得模糊匹配。
    @Test func doesNotFuzzyMatchAnotherServer() {
        let target = locateSingleShareTarget(identity: "//files.example:1445/docs", in: configuration())
        #expect(target == .unknownTarget)
        #expect(locateSingleShareTarget(identity: "//unknown.example/docs", in: configuration()) == .unknownTarget)
        #expect(locateSingleShareTarget(identity: "//files.example/other", in: configuration()) == .unknownTarget)
        #expect(locateSingleShareTarget(identity: "//files.example/docs", in: AutomntConfig()) == .unknownTarget)
    }

    // MARK: - 并发变更拒绝

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("automnt-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// 命令先读 revision 再动作。这是它实际依赖的 CAS 门：并发保存后，
    /// 旧 revision 的许可必须被拒绝，且配置文件字节保持不变。
    @Test func staleRevisionIsRefusedWithoutOverwriting() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let first = try repository.create(configuration())

        // 另一个参与者并发保存了配置。
        var changed = first.configuration
        changed.hosts[0].alias = "renamed"
        let second = try repository.save(changed, baseRevision: first.revision)
        #expect(second.revision != first.revision)
        let bytesAfterChange = try PrivateAtomicFile.read(directory.appendingPathComponent("automnt.plist"))

        let backend = BackendStateStore(authorizedDirectory: directory)
        try backend.initialize(revision: second.revision)
        #expect(throws: AutomntIssue.configurationConflict) {
            _ = try EvaluationPermit(directory: directory, repository: repository,
                                     expected: first, owner: .none, generation: 0,
                                     readBackend: backend.read)
        }
        #expect(try PrivateAtomicFile.read(directory.appendingPathComponent("automnt.plist")) == bytesAfterChange)
        #expect(try repository.read().configuration.hosts[0].alias == "renamed")
    }

    /// 在途操作意图绑定 revision/generation：代次或修订不符时不得清账。
    @Test func inFlightOperationRefusesMismatchedRevision() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(configuration())
        let store = WorkerOperationStore(authorizedDirectory: directory)

        // 在途意图以 begin 记录（与弹出路径一致）。
        _ = try store.begin(revision: snapshot.revision, generation: 4)
        #expect(throws: AutomntIssue.configurationConflict) {
            try store.complete(id: UUID(), revision: snapshot.revision, generation: 4)
        }
        let otherRevision = ConfigRevision(digest: String(repeating: "0", count: 64))
        #expect(throws: AutomntIssue.configurationConflict) {
            try store.complete(id: UUID(), revision: otherRevision, generation: 4)
        }
        // 未知 id 一律不得清账；在途意图保持，下一操作仍被拒绝。
        #expect(throws: AutomntIssue.signalUnavailable) { try store.verifyIdle() }
    }

    /// 锁纪律回归：`EvaluationPermit` 持有 `evaluation.lock` 期间，
    /// `WorkerOperationStore` 取的是同一把**不可重入**的锁。因此真实代码路径
    /// 必须“先释放许可、再登记在途意图”，否则弹出会以 EWOULDBLOCK 自锁失败。
    @Test func permitHeldLockIsNotReentrantForWorkerOperationStore() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(configuration())
        let state = BackendState(owner: .cli, phase: .active, generation: 3, revision: snapshot.revision)

        let permit = try EvaluationPermit(directory: directory, repository: repository,
                                          expected: snapshot, owner: .cli, generation: 3) { state }
        // 许可持锁期间：在途意图登记必然被同一把锁拒绝（flock 不可重入）。
        let store = WorkerOperationStore(authorizedDirectory: directory)
        #expect(throws: (any Error).self) {
            _ = try store.begin(revision: snapshot.revision, generation: 3)
        }
        withExtendedLifetime(permit) {}
    }

    /// 许可释放后，在途意图读写恢复可用——这正是弹出父进程依赖的顺序。
    @Test func workerOperationStoreWorksAfterPermitReleased() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileConfigRepository(authorizedDirectory: directory)
        let snapshot = try repository.create(configuration())
        let state = BackendState(owner: .cli, phase: .active, generation: 3, revision: snapshot.revision)

        do {
            let permit = try EvaluationPermit(directory: directory, repository: repository,
                                              expected: snapshot, owner: .cli, generation: 3) { state }
            withExtendedLifetime(permit) {}
        }
        let store = WorkerOperationStore(authorizedDirectory: directory)
        let id = try store.begin(revision: snapshot.revision, generation: 3)
        try store.verifyPending(id: id, revision: snapshot.revision, generation: 3)
        try store.complete(id: id, revision: snapshot.revision, generation: 3)
        try store.verifyIdle()
    }

    // MARK: - 普通弹出失败分类

    /// 分类必须与 `AutomntPlatform.DiskArbitrationBackend` 完全一致。
    @Test func dissenterStatusMapsToTheSharedIssueVocabulary() {
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(kDAReturnBusy)) == .volumeBusy)
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(kDAReturnNotPermitted)) == .authorizationRequired)
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(kDAReturnNotReady)) == .shareRejected)
        #expect(cliNormalEjectIssue(forDissenterStatus: DAReturn(kDAReturnNotMounted)) == .shareRejected)
    }

    /// 非绝对路径、根路径、已过期预算都必须在触碰内核前被拒绝。
    @Test func ejectRefusesInvalidPathAndExpiredBudget() {
        #expect(performNormalEject(mountedIdentity: "//files.example/docs", path: "", deadline: Date().addingTimeInterval(5))
                == .failure(.pathConflict))
        #expect(performNormalEject(mountedIdentity: "//files.example/docs", path: "/", deadline: Date().addingTimeInterval(5))
                == .failure(.pathConflict))
        #expect(performNormalEject(mountedIdentity: "//files.example/docs", path: "relative/path",
                                  deadline: Date().addingTimeInterval(5)) == .failure(.pathConflict))
        #expect(performNormalEject(mountedIdentity: "//files.example/docs", path: "/Volumes/Docs",
                                  deadline: Date().addingTimeInterval(-1)) == .failure(.timeout))
    }

    /// 路径身份不合一时必须拒绝：仅凭“实际路径非空”不足以弹出。
    @Test func ejectRequiresTheExactMountedIdentity() {
        let unmounted = performNormalEject(mountedIdentity: "//files.example/docs", path: "/Volumes/NotMounted-AutomntTest",
                                           deadline: Date().addingTimeInterval(5))
        #expect(unmounted == .failure(.pathConflict))
    }

    // MARK: - 用户入口的拒绝路径（不触碰真实安装目录）

    /// 目标不在活动配置中：明确错误 + 非 0 退出码 + 配置字节不变。
    /// 该路径在取得所有权许可之前就返回，因此不产生任何系统副作用。
    @Test func commandRejectsUnknownTargetWithNonZeroExit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("automnt.plist")
        let repository = FileConfigRepository(authorizedDirectory: directory)
        _ = try repository.create(configuration())
        let before = try PrivateAtomicFile.read(configURL)

        let previousOverride = configURLOverride
        configURLOverride = configURL
        defer { configURLOverride = previousOverride }

        #expect(runSingleShareCommand(intent: .mount, arguments: ["smb://unknown.example/Docs"]) == 2)
        #expect(runSingleShareCommand(intent: .eject, arguments: ["smb://unknown.example/Docs"]) == 2)
        #expect(try PrivateAtomicFile.read(configURL) == before)
    }

    /// 用法错误同样以退出码 2 结束，且不读取或改动配置。
    @Test func commandRejectsUsageErrorsWithNonZeroExit() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("automnt.plist")
        _ = try FileConfigRepository(authorizedDirectory: directory).create(configuration())

        let previousOverride = configURLOverride
        configURLOverride = configURL
        defer { configURLOverride = previousOverride }

        #expect(runSingleShareCommand(intent: .mount, arguments: []) == 2)
        #expect(runSingleShareCommand(intent: .mount, arguments: ["smb://user:pw@files.example/Docs"]) == 2)
        #expect(runSingleShareCommand(intent: .mount, arguments: ["https://files.example/Docs"]) == 2)
        #expect(runSingleShareCommand(intent: .eject, arguments: []) == 2)
    }

    /// 配置缺失时不得隐式初始化，必须以退出码 2 结束并给出指引。
    @Test func commandRefusesWhenConfigurationIsMissing() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configURL = directory.appendingPathComponent("automnt.plist")

        let previousOverride = configURLOverride
        configURLOverride = configURL
        defer { configURLOverride = previousOverride }

        #expect(runSingleShareCommand(intent: .mount, arguments: ["smb://files.example/Docs"]) == 2)
        #expect(!FileManager.default.fileExists(atPath: configURL.path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("backend-state.plist").path))
    }

    // MARK: - 隔离子进程的结论解析

    /// 父进程只信子进程明确写出的结论行；无法解析一律保守视为需修复，
    /// 绝不把“没看懂”当成“已弹出”。
    @Test func childResultParsingIsConservative() {
        #expect(cliChildEjectIssue(fromChildOutput: "ok\n") == nil)
        #expect(cliChildEjectIssue(fromChildOutput: "note\nok") == nil)
        #expect(cliChildEjectIssue(fromChildOutput: "issue:volumeBusy\n") == .volumeBusy)
        #expect(cliChildEjectIssue(fromChildOutput: "noise\nissue:pathConflict\n") == .pathConflict)
        #expect(cliChildEjectIssue(fromChildOutput: "") == .signalUnavailable)
        #expect(cliChildEjectIssue(fromChildOutput: "okay\n") == .signalUnavailable)
        #expect(cliChildEjectIssue(fromChildOutput: "issue:notARealIssue") == .signalUnavailable)
        // 空行结尾不得改变结论。
        #expect(cliChildEjectIssue(fromChildOutput: "issue:volumeBusy\n\n") == .volumeBusy)
    }

    /// 内部子命令的参数必须严格；非法调用以退出码 64（用法错误）结束，不触碰任何状态。
    @Test func internalEjectRejectsMalformedArguments() {
        #expect(runInternalNormalEject(arguments: []) == 64)
        #expect(runInternalNormalEject(arguments: ["/Volumes/Docs"]) == 64)
        #expect(runInternalNormalEject(arguments: ["/Volumes/Docs", "//a.example/docs"]) == 64)
        #expect(runInternalNormalEject(arguments: ["/Volumes/Docs", "//a.example/docs", "not-a-uuid"]) == 64)
        #expect(runInternalNormalEject(arguments: ["relative", "//a.example/docs", UUID().uuidString]) == 64)
        #expect(runInternalNormalEject(arguments: ["/", "//a.example/docs", UUID().uuidString]) == 64)
    }

    // MARK: - 帮助文本

    /// 帮助必须同时说明两个新入口与弹出语义（普通弹出、繁忙失败、尊重意愿）。
    /// 断言对两种界面语言都成立，避免依赖运行环境的 Locale。
    @Test func helpDocumentsBothEntriesAndEjectSemantics() {
        let help = usageText()
        #expect(help.contains("--mount <smb-url>"))
        #expect(help.contains("--eject <smb-url>"))
        // 普通弹出语义：要么中文“普通弹出”，要么英文 “Ordinary eject”。
        #expect(help.contains("普通弹出") || help.contains("Ordinary eject"))
        // 非强制：绝不 force / never forced。
        #expect(help.contains("非强制") || help.contains("never forced"))
        // 尊重用户意愿并如实报告繁忙。
        #expect(help.contains("尊重本次会话的弹出意愿") || help.contains("your intent is respected"))
        #expect(help.contains("占用") || help.contains("in use"))
    }
}
