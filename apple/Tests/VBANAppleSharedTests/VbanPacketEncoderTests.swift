import Foundation
import Testing
@testable import VBANAppleShared

struct VbanPacketEncoderTests {
    @Test func packetHeaderMatchesAndroidLayout() throws {
        var encoder = try VbanPacketEncoder(streamName: "SteamDeck")
        let pcm = Data(repeating: 0x34, count: VbanConstants.pcmBytesPerPacket)

        let packet = try encoder.encodePcm16Stereo(pcm)

        #expect(packet.count == VbanConstants.headerSize + pcm.count)
        #expect(Array(packet[0..<4]) == [0x56, 0x42, 0x41, 0x4E])
        #expect(packet[4] == 3)
        #expect(packet[5] == 255)
        #expect(packet[6] == 1)
        #expect(packet[7] == 1)

        let streamBytes = Array(packet[8..<24])
        #expect(streamBytes[0] == 0x53)
        #expect(streamBytes[8] == 0x6B)
        #expect(streamBytes[9] == 0x00)

        let counter = packet[24..<28].withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self)
        }
        #expect(counter == 0)
    }

    @Test func frameCounterAdvances() throws {
        var encoder = try VbanPacketEncoder(streamName: "iPhone")
        let pcm = Data(repeating: 0x00, count: 4)

        _ = try encoder.encodePcm16Stereo(pcm)
        let secondPacket = try encoder.encodePcm16Stereo(pcm)

        let counter = secondPacket[24..<28].withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self)
        }
        #expect(counter == 1)
    }
}
