import Foundation

/// Nonzero launchctl results are not generally evidence of service release.
public enum LaunchAgentPresence: Equatable, Sendable {
    case registered
    case absent
    case unknown

    public static func classify(status: Int32?, timedOut: Bool, processStopped: Bool,
                                standardError: String, serviceLabel: String) -> Self {
        guard !timedOut, processStopped, let status else { return .unknown }
        if status == 0 { return .registered }
        guard status == 113,
              standardError.contains("Could not find service \"\(serviceLabel)\" in domain") else { return .unknown }
        return .absent
    }
}
