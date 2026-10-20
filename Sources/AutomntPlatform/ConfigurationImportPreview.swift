import Foundation
import AutomntCore

/// Reads only a user-selected file; neither the source nor app configuration changes.
public struct ConfigurationImportPreview: Sendable {
    public let configuration: AutomntConfig
    public let source: Data

    public init(selectedFile: URL) throws {
        let scoped = selectedFile.startAccessingSecurityScopedResource()
        defer { if scoped { selectedFile.stopAccessingSecurityScopedResource() } }
        let metadata = try selectedFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard metadata.isRegularFile == true, metadata.isSymbolicLink != true,
              let size = metadata.fileSize, size > 0, size <= 1_048_576 else {
            throw AutomntIssue.invalidConfiguration
        }
        let data = try PrivateAtomicFile.read(selectedFile, maximumBytes: 1_048_576)
        guard data.count <= 1_048_576 else { throw AutomntIssue.invalidConfiguration }
        try ConfigurationPrivacy.validate(PropertyListSerialization.propertyList(from: data, format: nil))
        let configuration = try PropertyListDecoder().decode(AutomntConfig.self, from: data)
        guard ConfigurationValidation.problems(in: configuration).isEmpty else { throw AutomntIssue.invalidConfiguration }
        self.configuration = configuration
        self.source = data
    }
}
