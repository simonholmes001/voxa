import XCTest
@testable import VoxaRealtime

final class PCM16AudioProcessorTests: XCTestCase {
    func testAmplifiesPcmSamples() {
        let input = data(samples: [1_000, -1_000])
        let output = PCM16AudioProcessor.amplified(input, gain: 2)
        XCTAssertEqual(samples(output), [2_000, -2_000])
    }

    func testLimitsAmplifiedSamplesWithoutWrapping() {
        let output = PCM16AudioProcessor.amplified(data(samples: [20_000, -20_000]), gain: 2, limit: 30_000)
        XCTAssertEqual(samples(output), [30_000, -30_000])
    }

    private func data(samples: [Int16]) -> Data {
        samples.reduce(into: Data()) { result, sample in
            result.append(UInt8(truncatingIfNeeded: sample))
            result.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
    }

    private func samples(_ data: Data) -> [Int16] {
        stride(from: 0, to: data.count, by: 2).map {
            Int16(bitPattern: UInt16(data[$0]) | (UInt16(data[$0 + 1]) << 8))
        }
    }
}
