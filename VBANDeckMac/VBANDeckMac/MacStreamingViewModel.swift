import AudioToolbox
import Combine
import CoreMedia
import Foundation
import ScreenCaptureKit
import SwiftUI
import VBANAppleShared

@MainActor
final class MacStreamingViewModel: ObservableObject {
    @Published var host = ""
    @Published var port = 6980
    @Published var streamName = "MacBook"
    @Published var captureSystemAudio = true
    @Published var status = "Ready to configure ScreenCaptureKit capture"
    @Published var isStreaming = false

    private var coordinator: MacAudioCaptureCoordinator?
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func startStreaming() async {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Destination IP is required"
            return
        }
        guard captureSystemAudio else {
            status = "System audio capture must stay enabled for the macOS sender"
            return
        }

        do {
            let config = try SenderConfiguration(host: host, port: UInt16(port), streamName: streamName)
            let coordinator = MacAudioCaptureCoordinator()
            coordinator.onStatus = { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.status = message
                }
            }
            coordinator.onStop = { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.coordinator = nil
                    self?.isStreaming = false
                    self?.status = message
                }
            }

            try await coordinator.start(configuration: config)
            save()
            self.coordinator = coordinator
            isStreaming = true
            status = "Streaming 48 kHz stereo system audio to \(host):\(port)"
        } catch {
            status = "Unable to start: \(error.localizedDescription)"
            isStreaming = false
            coordinator = nil
        }
    }

    func stopStreaming() {
        guard let coordinator else {
            isStreaming = false
            status = "Stopped"
            return
        }

        self.coordinator = nil
        isStreaming = false
        status = "Stopping…"
        Task {
            await coordinator.stop()
            await MainActor.run {
                if !self.isStreaming {
                    self.status = "Stopped"
                }
            }
        }
    }

    private func load() {
        if let host = defaults.string(forKey: "mac.host") {
            self.host = host
        }
        let savedPort = defaults.integer(forKey: "mac.port")
        if savedPort != 0 {
            self.port = savedPort
        }
        if let streamName = defaults.string(forKey: "mac.streamName") {
            self.streamName = streamName
        }
    }

    private func save() {
        defaults.set(host, forKey: "mac.host")
        defaults.set(port, forKey: "mac.port")
        defaults.set(streamName, forKey: "mac.streamName")
    }
}

private final class MacAudioCaptureCoordinator: NSObject, SCStreamOutput, SCStreamDelegate {
    var onStatus: ((String) -> Void)?
    var onStop: ((String) -> Void)?

    private let sampleQueue = DispatchQueue(label: "com.tee215.vbandeck.macos.audio")
    private var sender: VbanSender?
    private var stream: SCStream?
    private var pcmAccumulator = Data()
    private var isStopping = false
    private var packetCount = 0
    private var audioCallbackCount = 0
    private var hasReportedAudioFlow = false

    func start(configuration: SenderConfiguration) async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw MacStreamingError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = 2
        streamConfig.height = 2
        streamConfig.queueDepth = 3
        streamConfig.showsCursor = false
        streamConfig.capturesAudio = true
        streamConfig.sampleRate = VbanConstants.sampleRate
        streamConfig.channelCount = VbanConstants.channels
        streamConfig.excludesCurrentProcessAudio = true

        let sender = try VbanSender(configuration: configuration)
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)

        do {
            try await addScreenOutput(to: stream)
            try await addAudioOutput(to: stream)
            try await startCapture(on: stream)
        } catch {
            await stopStreamIfNeeded(stream)
            throw error
        }

        self.sender = sender
        self.stream = stream
        onStatus?("Screen capture permission granted; waiting for audio callbacks")
    }

    func stop() async {
        guard let stream else {
            pcmAccumulator.removeAll(keepingCapacity: false)
            sender = nil
            return
        }

        isStopping = true
        await stopStreamIfNeeded(stream)
        self.stream = nil
        self.sender = nil
        self.pcmAccumulator.removeAll(keepingCapacity: false)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else {
            return
        }

        do {
            let pcm = try convertToPcm16Stereo(sampleBuffer: sampleBuffer)
            guard !pcm.isEmpty else {
                return
            }
            audioCallbackCount += 1
            if !hasReportedAudioFlow {
                hasReportedAudioFlow = true
                onStatus?("Audio callbacks started; building VBAN packets")
            }
            pcmAccumulator.append(pcm)
            drainPacketsIfNeeded()
        } catch {
            fail(message: "Audio conversion failed: \(error.localizedDescription)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fail(message: "Capture stopped: \(error.localizedDescription)")
    }

    private func addAudioOutput(to stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func addScreenOutput(to stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func startCapture(on stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func stopStreamIfNeeded(_ stream: SCStream) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stopCapture { _ in
                continuation.resume()
            }
        }
    }

    private func drainPacketsIfNeeded() {
        while pcmAccumulator.count >= VbanConstants.pcmBytesPerPacket {
            let packet = Data(pcmAccumulator.prefix(VbanConstants.pcmBytesPerPacket))
            pcmAccumulator.removeFirst(VbanConstants.pcmBytesPerPacket)
            guard let sender else {
                continue
            }
            Task {
                do {
                    try await sender.sendPcm16Stereo(packet)
                    self.packetCount += 1
                    if self.packetCount == 1 || self.packetCount % 100 == 0 {
                        self.onStatus?("Sending VBAN audio: \(self.packetCount) packets, \(self.audioCallbackCount) callbacks")
                    }
                } catch {
                    self.fail(message: "VBAN send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func fail(message: String) {
        guard !isStopping else {
            return
        }

        isStopping = true
        onStatus?(message)
        Task {
            if let stream {
                await stopStreamIfNeeded(stream)
            }
            self.stream = nil
            self.sender = nil
            self.pcmAccumulator.removeAll(keepingCapacity: false)
            self.onStop?(message)
        }
    }

    private func convertToPcm16Stereo(sampleBuffer: CMSampleBuffer) throws -> Data {
        guard CMSampleBufferIsValid(sampleBuffer) else {
            throw MacStreamingError.invalidSampleBuffer
        }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw MacStreamingError.missingAudioFormat
        }

        let asbd = asbdPointer.pointee
        guard Int(asbd.mSampleRate.rounded()) == VbanConstants.sampleRate else {
            throw MacStreamingError.unsupportedSampleRate(Int(asbd.mSampleRate.rounded()))
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            return Data()
        }

        let audioBufferListSize = MemoryLayout<AudioBufferList>.size +
            max(0, Int(asbd.mChannelsPerFrame) - 1) * MemoryLayout<AudioBuffer>.size
        let audioBufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { audioBufferListPointer.deallocate() }

        let audioBufferList = audioBufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        var sizeNeeded = 0
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: audioBufferList,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            throw MacStreamingError.audioBufferExtractionFailed(status)
        }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return try makeInterleavedPcm16(from: buffers, asbd: asbd, frameCount: frameCount)
    }

    private func makeInterleavedPcm16(
        from buffers: UnsafeMutableAudioBufferListPointer,
        asbd: AudioStreamBasicDescription,
        frameCount: Int
    ) throws -> Data {
        let inputChannels = max(1, Int(asbd.mChannelsPerFrame))
        let bytesPerChannel = max(1, Int(asbd.mBitsPerChannel / 8))
        let bytesPerFrame = max(bytesPerChannel * inputChannels, Int(asbd.mBytesPerFrame))
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        guard isFloat || isSignedInteger else {
            throw MacStreamingError.unsupportedAudioFormat
        }

        var output = Data(count: frameCount * VbanConstants.channels * VbanConstants.bytesPerSample)
        output.withUnsafeMutableBytes { outputBytes in
            guard let baseAddress = outputBytes.baseAddress else {
                return
            }
            let samples = baseAddress.assumingMemoryBound(to: Int16.self)

            for frame in 0..<frameCount {
                let left = normalizedSample(
                    channel: 0,
                    frame: frame,
                    buffers: buffers,
                    bytesPerChannel: bytesPerChannel,
                    bytesPerFrame: bytesPerFrame,
                    isFloat: isFloat,
                    isNonInterleaved: isNonInterleaved
                )
                let rightSourceChannel = min(1, inputChannels - 1)
                let right = normalizedSample(
                    channel: rightSourceChannel,
                    frame: frame,
                    buffers: buffers,
                    bytesPerChannel: bytesPerChannel,
                    bytesPerFrame: bytesPerFrame,
                    isFloat: isFloat,
                    isNonInterleaved: isNonInterleaved
                )

                samples[(frame * 2)] = pcm16(from: left)
                samples[(frame * 2) + 1] = pcm16(from: right)
            }
        }
        return output
    }

    private func normalizedSample(
        channel: Int,
        frame: Int,
        buffers: UnsafeMutableAudioBufferListPointer,
        bytesPerChannel: Int,
        bytesPerFrame: Int,
        isFloat: Bool,
        isNonInterleaved: Bool
    ) -> Double {
        let bufferIndex = isNonInterleaved ? min(channel, buffers.count - 1) : 0
        let buffer = buffers[bufferIndex]
        guard let baseAddress = buffer.mData else {
            return 0
        }

        let offset = isNonInterleaved
            ? frame * bytesPerChannel
            : (frame * bytesPerFrame) + (channel * bytesPerChannel)
        guard offset + bytesPerChannel <= Int(buffer.mDataByteSize) else {
            return 0
        }

        let samplePointer = baseAddress.advanced(by: offset)
        if isFloat {
            switch bytesPerChannel {
            case 4:
                return Double(samplePointer.assumingMemoryBound(to: Float.self).pointee)
            case 8:
                return samplePointer.assumingMemoryBound(to: Double.self).pointee
            default:
                return 0
            }
        }

        switch bytesPerChannel {
        case 2:
            let raw = samplePointer.assumingMemoryBound(to: Int16.self).pointee
            return Double(raw) / Double(Int16.max)
        case 3:
            let bytes = samplePointer.assumingMemoryBound(to: UInt8.self)
            let raw = Int32(bytes[0]) | (Int32(bytes[1]) << 8) | (Int32(bytes[2]) << 16)
            let signed = (raw & 0x800000) != 0 ? (raw | ~0xFFFFFF) : raw
            return Double(signed) / Double(0x7FFFFF)
        case 4:
            let raw = samplePointer.assumingMemoryBound(to: Int32.self).pointee
            return Double(raw) / Double(Int32.max)
        default:
            return 0
        }
    }

    private func pcm16(from normalized: Double) -> Int16 {
        let clamped = max(-1.0, min(1.0, normalized))
        let scaled = clamped * Double(Int16.max)
        return Int16(scaled.rounded())
    }
}

private enum MacStreamingError: LocalizedError {
    case noDisplayAvailable
    case invalidSampleBuffer
    case missingAudioFormat
    case unsupportedSampleRate(Int)
    case audioBufferExtractionFailed(OSStatus)
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No shareable display was available for ScreenCaptureKit."
        case .invalidSampleBuffer:
            return "ScreenCaptureKit returned an invalid audio buffer."
        case .missingAudioFormat:
            return "Missing audio format description from ScreenCaptureKit."
        case .unsupportedSampleRate(let sampleRate):
            return "Expected 48000 Hz capture but received \(sampleRate) Hz."
        case .audioBufferExtractionFailed(let status):
            return "Failed to extract audio buffers (\(status))."
        case .unsupportedAudioFormat:
            return "Unsupported ScreenCaptureKit audio sample format."
        }
    }
}
