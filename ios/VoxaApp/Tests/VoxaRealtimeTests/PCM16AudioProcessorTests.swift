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

    func testDecodesInt16PcmToNormalizedFloat32() {
        let input = data(samples: [0, Int16.max, Int16.min + 1, Int16.max / 2])
        let output = PCM16AudioProcessor.decodeToFloat32(input)
        XCTAssertEqual(output.count, 4)
        XCTAssertEqual(output[0], 0, accuracy: 0.0001)
        XCTAssertEqual(output[1], 1.0, accuracy: 0.0001)
        // (Int16.min + 1) / Int16.max is -1.0 exactly.
        XCTAssertEqual(output[2], -1.0, accuracy: 0.0001)
        XCTAssertEqual(output[3], 0.5, accuracy: 0.001)
    }

    func testDecodesUnalignedDataWithoutCrashingOrCorrupting() {
        // Base64-decoded WebSocket audio can land on `Data` whose underlying
        // storage is not 2-byte aligned. Simulate that by taking a subrange
        // starting at an odd byte offset and asserting the samples are still
        // read correctly (byte-safe subscripting, not typed pointer load).
        var leading = Data([0xAA])
        leading.append(data(samples: [1_234, -5_678, 32_000]))
        let unaligned = leading.subdata(in: 1..<leading.count)
        let output = PCM16AudioProcessor.decodeToFloat32(unaligned)
        XCTAssertEqual(output.count, 3)
        XCTAssertEqual(output[0], Float(1_234) / Float(Int16.max), accuracy: 0.0001)
        XCTAssertEqual(output[1], Float(-5_678) / Float(Int16.max), accuracy: 0.0001)
        XCTAssertEqual(output[2], Float(32_000) / Float(Int16.max), accuracy: 0.0001)
    }

    func testDecodesOddByteCountByDroppingTrailingByte() {
        var input = data(samples: [4_096])
        input.append(0xFF)  // stray trailing byte
        let output = PCM16AudioProcessor.decodeToFloat32(input)
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output[0], Float(4_096) / Float(Int16.max), accuracy: 0.0001)
    }

    func testDecodesEmptyDataToEmptyArray() {
        XCTAssertEqual(PCM16AudioProcessor.decodeToFloat32(Data()), [])
        XCTAssertEqual(PCM16AudioProcessor.decodeToFloat32(Data([0x00])), [])
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
