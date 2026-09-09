import Foundation

/// Deterministic PCM processing kept separate from AVAudioEngine so it can be
/// tested without a device or speaker route.
public enum PCM16AudioProcessor {
    public static func amplified(_ data: Data, gain: Float, limit: Int16 = 30_000) -> Data {
        guard data.count >= 2 else { return data }
        let clampedGain = max(0, gain)
        var output = Data(capacity: data.count)
        for offset in stride(from: 0, to: data.count - 1, by: 2) {
            let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            let value = max(-Float(limit), min(Float(limit), Float(raw) * clampedGain))
            let sample = Int16(value.rounded())
            output.append(UInt8(truncatingIfNeeded: sample))
            output.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        if data.count.isMultiple(of: 2) { return output }
        output.append(data.last!)
        return output
    }

    /// Decodes little-endian Int16 PCM bytes into Float32 samples normalized
    /// to [-1.0, 1.0]. Reads bytes with per-offset `data[offset]` subscripting
    /// rather than binding the raw `Data` storage to `Int16.self`, so it is
    /// safe on `Data` buffers whose underlying storage is not 2-byte aligned
    /// (as happens with base64-decoded WebSocket audio deltas).
    ///
    /// Any trailing odd byte is dropped; the returned array holds exactly
    /// `data.count / 2` samples.
    public static func decodeToFloat32(_ data: Data) -> [Float] {
        let sampleCount = data.count / 2
        guard sampleCount > 0 else { return [] }
        var samples = [Float](repeating: 0, count: sampleCount)
        let scale = 1.0 / Float(Int16.max)
        for index in 0..<sampleCount {
            let offset = index * 2
            let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            samples[index] = Float(raw) * scale
        }
        return samples
    }
}
