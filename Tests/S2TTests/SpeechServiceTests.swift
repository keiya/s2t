import Testing
import Foundation
@testable import S2T

@Suite("SpeechService tests")
struct SpeechServiceTests {

    @Test
    func wavHeaderStructure() {
        // Create some fake PCM data (4 bytes = 2 samples at 16-bit)
        let pcmData = Data([0x00, 0x01, 0x02, 0x03])
        let wav = SpeechService.createWAVData(from: pcmData)

        // WAV should be 44 bytes header + pcm data
        #expect(wav.count == 44 + pcmData.count)

        // Check RIFF header
        let riff = String(data: wav[0..<4], encoding: .ascii)
        #expect(riff == "RIFF")

        // Check WAVE format
        let wave = String(data: wav[8..<12], encoding: .ascii)
        #expect(wave == "WAVE")

        // Check fmt sub-chunk
        let fmt = String(data: wav[12..<16], encoding: .ascii)
        #expect(fmt == "fmt ")

        // Check data sub-chunk
        let dataMarker = String(data: wav[36..<40], encoding: .ascii)
        #expect(dataMarker == "data")

        // Check file size field (offset 4, 4 bytes LE) = total - 8
        let fileSize = wav.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 4, as: UInt32.self).littleEndian
        }
        #expect(fileSize == UInt32(wav.count - 8))
    }

    @Test
    func wavHeaderSampleRate() {
        let pcmData = Data(repeating: 0, count: 100)
        let wav = SpeechService.createWAVData(from: pcmData)

        // Sample rate at offset 24, 4 bytes LE
        let sampleRate = wav.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 24, as: UInt32.self).littleEndian
        }
        #expect(sampleRate == 16000)

        // Channels at offset 22, 2 bytes LE
        let channels = wav.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 22, as: UInt16.self).littleEndian
        }
        #expect(channels == 1)

        // Bits per sample at offset 34, 2 bytes LE
        let bitsPerSample = wav.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 34, as: UInt16.self).littleEndian
        }
        #expect(bitsPerSample == 16)
    }

    @Test
    func wavHeaderPCMFormat() {
        let pcmData = Data(repeating: 0, count: 50)
        let wav = SpeechService.createWAVData(from: pcmData)

        // Audio format at offset 20, 2 bytes LE — should be 1 (PCM)
        let format = wav.withUnsafeBytes { ptr -> UInt16 in
            ptr.load(fromByteOffset: 20, as: UInt16.self).littleEndian
        }
        #expect(format == 1)
    }

    @Test
    func wavDataSizeField() {
        let pcmData = Data(repeating: 0xAB, count: 256)
        let wav = SpeechService.createWAVData(from: pcmData)

        // Data chunk size at offset 40, 4 bytes LE
        let dataSize = wav.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 40, as: UInt32.self).littleEndian
        }
        #expect(dataSize == 256)
    }

    @Test
    func emptyPCMProducesValidWAV() {
        let wav = SpeechService.createWAVData(from: Data())
        #expect(wav.count == 44) // header only
        let dataSize = wav.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 40, as: UInt32.self).littleEndian
        }
        #expect(dataSize == 0)
    }
}
