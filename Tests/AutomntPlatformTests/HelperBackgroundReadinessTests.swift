import Foundation
import Testing
import AutomntCore
@testable import AutomntPlatform

struct BundledServiceDefinitionTests {
    private func plist(agent: BundledAgent) -> [String: Any] {
        ["Label": agent.label,
         "BundleProgram": "Contents/Helpers/AutomntHelper",
         "RunAtLoad": true,
         "WatchPaths": ["/Library/Preferences/SystemConfiguration/NetworkInterfaces.plist"]]
    }

    @Test func acceptsOnlyTheFixedBundledAgentForm() {
        for agent in BundledAgent.allCases {
            #expect(BundledServiceDefinition.accepts(plist(agent: agent), agent: agent))
            #expect(!BundledServiceDefinition.accepts(plist(agent: agent), agent: agent == .baseline ? .recovery : .baseline))
        }
        var inlineProgram = plist(agent: .recovery)
        inlineProgram["ProgramArguments"] = ["/tmp/elsewhere"]
        #expect(!BundledServiceDefinition.accepts(inlineProgram, agent: .recovery))

        var wrongProgram = plist(agent: .recovery)
        wrongProgram["BundleProgram"] = "Contents/MacOS/Automnt"
        #expect(!BundledServiceDefinition.accepts(wrongProgram, agent: .recovery))

        var noRunAtLoad = plist(agent: .recovery)
        noRunAtLoad.removeValue(forKey: "RunAtLoad")
        #expect(!BundledServiceDefinition.accepts(noRunAtLoad, agent: .recovery))
    }

    @Test func definitionPathsStayInsideTheResolvedApplicationBundle() {
        let application = URL(fileURLWithPath: "/Applications/Automnt.app")
        #expect(BundledServiceDefinition.plistURL(applicationURL: application, agent: .recovery).path
            == "/Applications/Automnt.app/Contents/Library/LaunchAgents/automnt.recovery.plist")
        #expect(BundledServiceDefinition.helperURL(applicationURL: application).path
            == "/Applications/Automnt.app/Contents/Helpers/AutomntHelper")
    }
}

struct HelperBackgroundReadinessTests {
    private func activeState() -> BackendState {
        var state = BackendState(owner: .app, phase: .active, generation: 4,
            revision: ConfigRevision(digest: UUID().uuidString))
        state.desiredOwner = .app
        state.lastVerifiedServiceStatus = .enabled
        return state
    }

    private func readiness(label: String?, definitionVerified: Bool = true) -> HelperBackgroundReadiness {
        HelperBackgroundReadiness(applicationURL: URL(fileURLWithPath: "/Applications/Automnt.app"),
            launchedServiceLabel: label, definitionVerified: definitionVerified)
    }

    @Test func enabledOnlyWhenLaunchIdentityDefinitionAndBackendStateAllAgree() {
        var configuration = AutomntConfig()
        configuration.autoMountRecovery = true
        let state = activeState()
        #expect(readiness(label: "org.automnt.automnt.recovery").status(configuration: configuration, backend: state) == .enabled)

        // A stale opposite job must never evaluate, even with a valid definition.
        #expect(readiness(label: "org.automnt.automnt.baseline").status(configuration: configuration, backend: state) == .unavailable)
        // Manual launches have no launchd label.
        #expect(readiness(label: nil).status(configuration: configuration, backend: state) == .unavailable)
        // Failed signature/definition verification fails closed.
        #expect(readiness(label: "org.automnt.automnt.recovery", definitionVerified: false)
            .status(configuration: configuration, backend: state) == .unavailable)
    }

    @Test func recoveryPreferenceSelectsTheExpectedAgent() {
        var configuration = AutomntConfig()
        configuration.autoMountRecovery = false
        let state = activeState()
        #expect(readiness(label: "org.automnt.automnt.baseline").status(configuration: configuration, backend: state) == .enabled)
        #expect(readiness(label: "org.automnt.automnt.recovery").status(configuration: configuration, backend: state) == .unavailable)
    }

    @Test func backendStateMustProveAnActiveAppOwnership() {
        var configuration = AutomntConfig()
        configuration.autoMountRecovery = true
        let label = "org.automnt.automnt.recovery"
        var state = activeState()
        state.phase = .stopping
        #expect(readiness(label: label).status(configuration: configuration, backend: state) == .unavailable)
        state = activeState()
        state.owner = .none
        #expect(readiness(label: label).status(configuration: configuration, backend: state) == .unavailable)
        state = activeState()
        state.lastVerifiedServiceStatus = .requiresApproval
        #expect(readiness(label: label).status(configuration: configuration, backend: state) == .unavailable)
        state = activeState()
        state.generation = 0
        #expect(readiness(label: label).status(configuration: configuration, backend: state) == .unavailable)
    }

    @Test func launchdLabelComesOnlyFromTheServiceEnvironment() {
        #expect(HelperBackgroundReadiness.launchedServiceLabel(in: ["XPC_SERVICE_NAME": "org.automnt.automnt.recovery"])
            == "org.automnt.automnt.recovery")
        #expect(HelperBackgroundReadiness.launchedServiceLabel(in: [:]) == nil)
        #expect(HelperBackgroundReadiness.launchedServiceLabel(in: ["XPC_SERVICE_NAME": ""]) == nil)
    }
}
