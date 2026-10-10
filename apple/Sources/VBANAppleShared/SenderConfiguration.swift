import Foundation

public struct SenderConfiguration: Sendable, Equatable {
    public let host: String
    public let port: UInt16
    public let streamName: String

    public init(host: String, port: UInt16 = 6980, streamName: String) throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStream = streamName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw SenderConfigurationError.emptyHost
        }
        guard let data = trimmedStream.data(using: .ascii), !data.isEmpty,
              data.count <= VbanConstants.maxStreamNameBytes else {
            throw SenderConfigurationError.invalidStreamName
        }

        self.host = trimmedHost
        self.port = port
        self.streamName = trimmedStream
    }
}

public enum SenderConfigurationError: Error {
    case emptyHost
    case invalidStreamName
}
