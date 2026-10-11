// SPDX-License-Identifier: GPL-3.0-only
// WAV encoding for the recording pipeline, desktop's src/shared/wav.ts in
// Swift: 16 kHz mono 16-bit PCM, the format Whisper-style endpoints
// expect, byte for byte what desktop writes (shared/wav-vectors.json).
import Foundation

public enum Wav {
    public static let targetSampleRate = 16_000

    /// Mono float samples (-1 to 1) as a complete WAV file.
    public static func encodePcm16(_ samples: [Float], sampleRate: Int) -> Data {
        let dataLength = samples.count * 2
        var data = Data(capacity: 44 + dataLength)
        func ascii(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func u32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) } }

        ascii("RIFF")
        u32(36 + dataLength)
        ascii("WAVE")
        ascii("fmt ")
        u32(16) // fmt chunk size
        u16(1) // PCM
        u16(1) // mono
        u32(sampleRate)
        u32(sampleRate * 2) // byte rate
        u16(2) // block align
        u16(16) // bits per sample
        ascii("data")
        u32(dataLength)

        for sample in samples {
            withUnsafeBytes(of: pcm16(sample).littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Clamp, scale by 32767, and round halves up, as desktop does. A NaN
    /// sample writes 0, as JavaScript's DataView does.
    static func pcm16(_ sample: Float) -> Int16 {
        let value = Double(sample)
        if value.isNaN { return 0 }
        return Int16(JS.round(Swift.max(-1, Swift.min(1, value)) * 32767))
    }
}
