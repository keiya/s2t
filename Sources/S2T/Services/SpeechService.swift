@preconcurrency import AVFoundation
import Accelerate
import Foundation
import os

/// Audio recording service using AVAudioEngine.
/// Not @MainActor, not actor — AVAudioEngine callbacks run on a realtime audio thread.
/// Uses OSAllocatedUnfairLock for thread-safe buffer access.
final class SpeechService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let bufferLock = OSAllocatedUnfairLock(initialState: [Float]())
    private var isCurrentlyRecording = false
    private var hardwareSampleRate: Double = 48000

    /// Current audio level (0.0–1.0), updated from the audio tap.
    let levelLock = OSAllocatedUnfairLock(initialState: Float(0))

    // Target format: 16kHz, 16-bit, mono (for OpenAI API)
    static let targetSampleRate: Double = 16000
    static let targetChannels: AVAudioChannelCount = 1
    static let bitsPerSample: UInt16 = 16

    // Minimum audio size to be useful (roughly 0.5 seconds at 16kHz/16-bit/mono)
    static let minimumAudioDataSize = 16000

    var currentLevel: Float {
        levelLock.withLock { $0 }
    }

    func startRecording() throws {
        guard !isCurrentlyRecording else {
            Logger.audio.warning("Already recording, ignoring startRecording call")
            return
        }

        bufferLock.withLock { $0 = [] }
        levelLock.withLock { $0 = 0 }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            throw PipelineError.configurationError("No audio input device available")
        }

        hardwareSampleRate = hwFormat.sampleRate
        let channelCount = Int(hwFormat.channelCount)

        Logger.audio.error(
            "Hardware format: \(hwFormat.sampleRate, privacy: .public)Hz, \(hwFormat.channelCount, privacy: .public)ch"
        )

        // Tap in hardware format (nil) — guaranteed to work with any device.
        // We handle downmix + resample ourselves.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) {
            [bufferLock, levelLock] buffer, _ in

            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }

            // Downmix to mono: average all channels
            var mono = [Float](repeating: 0, count: frameCount)

            if let floatData = buffer.floatChannelData {
                for ch in 0..<channelCount {
                    let chPtr = floatData[ch]
                    for i in 0..<frameCount {
                        mono[i] += chPtr[i]
                    }
                }
                let scale = 1.0 / Float(channelCount)
                for i in 0..<frameCount {
                    mono[i] *= scale
                }
            } else if let int16Data = buffer.int16ChannelData {
                // Fallback for int16 hardware
                let scale = 1.0 / (Float(Int16.max) * Float(channelCount))
                for ch in 0..<channelCount {
                    let chPtr = int16Data[ch]
                    for i in 0..<frameCount {
                        mono[i] += Float(chPtr[i]) * scale
                    }
                }
            }

            // RMS level for meter
            var sumSq: Float = 0
            vDSP_measqv(mono, 1, &sumSq, vDSP_Length(frameCount))
            let rms = sumSq.squareRoot()
            levelLock.withLock { $0 = min(rms * 3, 1.0) }

            // Append mono float samples (resample later in stopRecording)
            let captured = mono
            bufferLock.withLock { $0.append(contentsOf: captured) }
        }

        try engine.start()
        isCurrentlyRecording = true
        Logger.audio.error("Recording started")
    }

    func stopRecording() -> Data {
        guard isCurrentlyRecording else {
            Logger.audio.warning("Not recording, returning empty data")
            return Data()
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCurrentlyRecording = false
        levelLock.withLock { $0 = 0 }

        let monoFloat = bufferLock.withLock { samples -> [Float] in
            let copy = samples
            samples = []
            return copy
        }

        // Resample from hardware rate to target rate
        let resampled = Self.resample(
            monoFloat,
            fromRate: hardwareSampleRate,
            toRate: Self.targetSampleRate
        )

        // Convert float to Int16 PCM
        var pcmData = Data(capacity: resampled.count * MemoryLayout<Int16>.size)
        var peak: Int16 = 0
        for sample in resampled {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            if abs(int16) > peak { peak = abs(int16) }
            Swift.withUnsafeBytes(of: int16.littleEndian) { pcmData.append(contentsOf: $0) }
        }

        let wavData = Self.createWAVData(from: pcmData)

        Logger.audio.error(
            "Recording stopped: \(pcmData.count, privacy: .public) bytes PCM, \(wavData.count, privacy: .public) bytes WAV, peak=\(peak, privacy: .public)"
        )

        // Debug: save WAV to /tmp for playback verification
        try? wavData.write(to: URL(fileURLWithPath: "/tmp/s2t_debug.wav"))

        return wavData
    }

    var isRecording: Bool { isCurrentlyRecording }

    // MARK: - Resample

    /// Simple linear-interpolation resample.
    static func resample(_ input: [Float], fromRate: Double, toRate: Double) -> [Float] {
        guard !input.isEmpty, fromRate > 0, toRate > 0 else { return [] }
        if fromRate == toRate { return input }

        let ratio = fromRate / toRate
        let outputCount = Int(Double(input.count) / ratio)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIndex = Double(i) * ratio
            let idx0 = Int(srcIndex)
            let frac = Float(srcIndex - Double(idx0))
            let idx1 = min(idx0 + 1, input.count - 1)
            output[i] = input[idx0] * (1.0 - frac) + input[idx1] * frac
        }
        return output
    }

    // MARK: - WAV Encoding

    /// Create WAV file data with a 44-byte RIFF header + raw PCM.
    static func createWAVData(from pcmData: Data) -> Data {
        let sampleRate: UInt32 = UInt32(targetSampleRate)
        let channels: UInt16 = UInt16(targetChannels)
        let bps: UInt16 = bitsPerSample
        let byteRate = sampleRate * UInt32(channels) * UInt32(bps) / 8
        let blockAlign = channels * bps / 8
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var header = Data(capacity: 44)

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.appendLittleEndianUInt32(fileSize)
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        header.appendLittleEndianUInt32(16) // sub-chunk size
        header.appendLittleEndianUInt16(1) // PCM format
        header.appendLittleEndianUInt16(channels)
        header.appendLittleEndianUInt32(sampleRate)
        header.appendLittleEndianUInt32(byteRate)
        header.appendLittleEndianUInt16(blockAlign)
        header.appendLittleEndianUInt16(bps)

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        header.appendLittleEndianUInt32(dataSize)

        return header + pcmData
    }
}

// MARK: - Data Extension for Little-Endian Writing

extension Data {
    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
