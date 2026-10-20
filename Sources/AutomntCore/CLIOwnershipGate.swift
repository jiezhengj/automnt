import Foundation

/// Which CLI capability is asking for the durable backend.
public enum CLIOwnershipAction: String, Equatable, Sendable {
    /// Install, self-heal or regenerate the traditional LaunchAgent definition.
    case registration
    /// Recovery round, baseline mount, explicit remount, manual eject or cleanup.
    case evaluation
    /// Read-only inspection of service status; never changes ownership.
    case status
    /// Uninstall / stop the traditional CLI service.
    case teardown
}

/// Pure, pre-system-call verdict derived from durable ownership facts.
///
/// This is the CLI-side counterpart of `ManualActionReadiness`: it never trusts
/// service liveness and never writes. The caller still revalidates under
/// `EvaluationPermit` immediately before the bounded operation.
public enum CLIOwnershipDecision: Equatable, Sendable {
    case permitted
    /// No durable `backend-state.plist` yet. The caller must initialize an
    /// explicit owner=none/stopped state instead of bypassing the store.
    case needsInitialization
    /// A durable app claim exists (owner or desired owner). The CLI must not
    /// register, self-heal or evaluate against it.
    case refusedAppOwner(BackendState.Phase)
    /// A previous transition failed; silently self-healing would erase evidence.
    case requiresRepair
    /// A durable transition is still stopping/activating.
    case transitionInFlight(BackendState.Phase)
    /// Durable state records a different configuration revision.
    case staleRevision(BackendState.Phase)
    /// The caller holds a snapshot from another backend generation.
    case staleGeneration
    /// Another bounded operation currently holds the shared operation lock.
    /// Concurrency protection, not damaged state: retry rather than repair.
    case operationInProgress
}

/// Owner-aware gate for the traditional (free, prebuilt) CLI channel.
///
/// Rules follow the ownership-transition contract: no automatic silent
/// takeover, no owner-blind self-healing, and no second active owner. The gate
/// is intentionally dependency-free so the CLI adapter and its tests share one
/// decision source.
public enum CLIOwnershipGate {
    public static func decide(action: CLIOwnershipAction, state: BackendState?,
                              revision: ConfigRevision,
                              expectedGeneration: UInt64? = nil) -> CLIOwnershipDecision {
        // Status is read-only and must stay available while the app owns the backend.
        if action == .status { return .permitted }
        guard let state else { return .needsInitialization }
        guard state.schemaVersion == 1 else { return .requiresRepair }
        if let expectedGeneration, state.generation != expectedGeneration { return .staleGeneration }

        if action == .teardown {
            return appClaim(state) ? .refusedAppOwner(state.phase) : .permitted
        }
        if appClaim(state) {
            // A failed app transition keeps its residual identity until an
            // explicit repair drains it. The CLI must never preempt that.
            return state.phase == .failed ? .requiresRepair : .refusedAppOwner(state.phase)
        }
        if state.phase == .failed { return .requiresRepair }
        if state.phase == .stopping || state.phase == .activating { return .transitionInFlight(state.phase) }
        if state.revision != revision { return .staleRevision(state.phase) }
        return .permitted
    }

    /// Runs `operation` only for a permitted verdict; otherwise throws before any
    /// system call or durable write. Tests use this to prove refusal has no side
    /// effects, and the CLI adapter uses the same path.
    @discardableResult
    public static func withPermission<T>(action: CLIOwnershipAction, state: BackendState?,
                                         revision: ConfigRevision,
                                         expectedGeneration: UInt64? = nil,
                                         operation: () throws -> T) throws -> T {
        switch decide(action: action, state: state, revision: revision, expectedGeneration: expectedGeneration) {
        case .permitted:
            return try operation()
        case .needsInitialization, .requiresRepair:
            throw AutomntIssue.serviceTransitionFailed
        case .refusedAppOwner:
            throw AutomntIssue.incompatibleOwner
        case .transitionInFlight, .staleRevision, .staleGeneration, .operationInProgress:
            throw AutomntIssue.configurationConflict
        }
    }

    /// The free CLI channel must stay event-driven: no resident KeepAlive and no
    /// periodic polling keys. Mirrors the single service-definition generator.
    public static func permitsNonResidentDefinition(_ definition: [String: Any]) -> Bool {
        definition["KeepAlive"] == nil
            && definition["StartInterval"] == nil
            && definition["StartCalendarInterval"] == nil
    }

    /// Whether the durable record carries an app claim (current or desired owner).
    /// Callers check this before any registration/self-heal system call.
    public static func refusesAppClaim(_ state: BackendState?) -> Bool {
        guard let state else { return false }
        return appClaim(state)
    }

    private static func appClaim(_ state: BackendState) -> Bool {
        state.owner == .app || state.desiredOwner == .app
    }
}

public extension CLIOwnershipDecision {
    /// Stable machine-readable tag; never contains user data.
    var tag: String {
        switch self {
        case .permitted: return "permitted"
        case .needsInitialization: return "needsInitialization"
        case .refusedAppOwner: return "refusedAppOwner"
        case .requiresRepair: return "requiresRepair"
        case .transitionInFlight: return "transitionInFlight"
        case .staleRevision: return "staleRevision"
        case .staleGeneration: return "staleGeneration"
        case .operationInProgress: return "operationInProgress"
        }
    }
}
