public enum VbanConstants {
    public static let sampleRate = 48_000
    public static let channels = 2
    public static let bytesPerSample = 2
    public static let framesPerPacket = 256
    public static let headerSize = 28
    public static let pcmBytesPerPacket = framesPerPacket * channels * bytesPerSample
    public static let formatBit = UInt8(1)
    public static let sampleRateProtocolByte = UInt8(3)
    public static let maxStreamNameBytes = 15
}
