import Foundation
import Network

public actor VbanSender {
    private let connection: NWConnection
    private var encoder: VbanPacketEncoder

    public init(configuration: SenderConfiguration) throws {
        let host = NWEndpoint.Host(configuration.host)
        let port = NWEndpoint.Port(rawValue: configuration.port)
        guard let port else {
            throw VbanSenderError.invalidPort
        }

        self.connection = NWConnection(host: host, port: port, using: .udp)
        self.encoder = try VbanPacketEncoder(streamName: configuration.streamName)
        self.connection.start(queue: .global(qos: .userInitiated))
    }

    deinit {
        connection.cancel()
    }

    public func sendPcm16Stereo(_ pcm: Data) async throws {
        let packet = try encoder.encodePcm16Stereo(pcm)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

public enum VbanSenderError: Error {
    case invalidPort
}
