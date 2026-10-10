import Foundation

public struct VbanPacketEncoder: Sendable {
    private let streamNameData: Data
    private var frameCounter: UInt32 = 0

    public init(streamName: String) throws {
        guard let data = streamName.data(using: .ascii), !data.isEmpty,
              data.count <= VbanConstants.maxStreamNameBytes else {
            throw SenderConfigurationError.invalidStreamName
        }
        self.streamNameData = data
    }

    public mutating func encodePcm16Stereo(_ pcm: Data) throws -> Data {
        guard pcm.count > 0, pcm.count % (VbanConstants.channels * VbanConstants.bytesPerSample) == 0 else {
            throw VbanPacketEncodingError.invalidPCMByteCount
        }

        let frames = pcm.count / (VbanConstants.channels * VbanConstants.bytesPerSample)
        guard (1...VbanConstants.framesPerPacket).contains(frames) else {
            throw VbanPacketEncodingError.invalidFrameCount
        }

        var packet = Data(capacity: VbanConstants.headerSize + pcm.count)
        packet.append(contentsOf: [0x56, 0x42, 0x41, 0x4E])
        packet.append(VbanConstants.sampleRateProtocolByte)
        packet.append(UInt8(frames - 1))
        packet.append(UInt8(VbanConstants.channels - 1))
        packet.append(VbanConstants.formatBit)

        var paddedStreamName = Data(repeating: 0, count: 16)
        paddedStreamName.replaceSubrange(0..<streamNameData.count, with: streamNameData)
        packet.append(paddedStreamName)

        var counterLE = frameCounter.littleEndian
        withUnsafeBytes(of: &counterLE) { packet.append(contentsOf: $0) }
        packet.append(pcm)
        frameCounter &+= 1
        return packet
    }
}

public enum VbanPacketEncodingError: Error {
    case invalidPCMByteCount
    case invalidFrameCount
}
