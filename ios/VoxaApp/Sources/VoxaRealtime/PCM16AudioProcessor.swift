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
}
