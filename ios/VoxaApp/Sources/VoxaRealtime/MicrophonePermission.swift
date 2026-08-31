/// The learner's microphone permission status.
public enum MicrophonePermissionStatus: Sendable, Equatable {
    case undetermined
    case granted
    case denied
}

/// Abstracts microphone permission so the Talk flow can be tested without the
/// system prompt.
public protocol MicrophonePermission: Sendable {
    func currentStatus() -> MicrophonePermissionStatus
    func request() async -> MicrophonePermissionStatus
}

#if os(iOS)
import AVFoundation

/// System microphone permission backed by `AVAudioApplication` (iOS 17+).
public struct SystemMicrophonePermission: MicrophonePermission {
    public init() {}

    public func currentStatus() -> MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    public func request() async -> MicrophonePermissionStatus {
        await AVAudioApplication.requestRecordPermission() ? .granted : .denied
    }
}
#endif
