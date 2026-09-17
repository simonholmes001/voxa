import XCTest
@testable import VoxaRealtimeWebRTC

final class WebSocketSessionUpdatePayloadTests: XCTestCase {
    func testSessionUpdateKeepsStrictVadPolicyWithoutMutableTutorSettings() throws {
        let data = Data(WebSocketRealtimeTransport.sessionUpdatePayload.utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "session.update")

        let session = try XCTUnwrap(object["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "realtime")
        XCTAssertNil(session["instructions"])
        XCTAssertNil(session["voice"])
        XCTAssertNil(session["speed"])
        XCTAssertNil(session["output_modalities"])

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        XCTAssertNil(audio["output"])

        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        XCTAssertNil(input["format"])

        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "whisper-1")

        let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turnDetection["type"] as? String, "server_vad")
        XCTAssertEqual(turnDetection["threshold"] as? Double, 0.85)
        XCTAssertEqual(turnDetection["prefix_padding_ms"] as? Int, 300)
        XCTAssertEqual(turnDetection["silence_duration_ms"] as? Int, 1500)
        XCTAssertEqual(turnDetection["create_response"] as? Bool, false)
        XCTAssertEqual(turnDetection["interrupt_response"] as? Bool, true)
    }
}
