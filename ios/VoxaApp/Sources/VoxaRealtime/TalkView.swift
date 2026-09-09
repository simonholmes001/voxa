#if canImport(SwiftUI)
import SwiftUI

/// The Talk screen: a voice session with the AI tutor. Shows the current
/// connection state and a primary control to start or end the session.
public struct TalkView: View {
    @Bindable private var model: TalkSessionViewModel

    public init(model: TalkSessionViewModel) {
        self.model = model
    }

    public var body: some View {
        // When a debrief is in flight or ready, it replaces the session-ended
        // panel. Errors show inline instead of blocking future sessions.
        switch model.debriefState {
        case .loading, .ready:
            SessionDebriefView(
                debriefState: model.debriefState,
                onStartNext: { intent in
                    model.prepare(intent)
                    Task { await model.start() }
                },
                onDismiss: { model.acknowledgeDebrief() },
                onRetry: { model.acknowledgeDebrief() })
        case .idle, .failed:
            sessionBody
        }
    }

    private var sessionBody: some View {
        VStack(spacing: 24) {
            Spacer()
            waveformIcon
            Text(statusTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            if case .connected = model.state {
                Text("Tap the wave to interrupt the tutor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("talk-interrupt-hint")
            }
            if !isSessionActive {
                Text(model.pendingIntent.title)
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("talk-intent-title")
            }
            if case let .failed(message) = model.state {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("talk-error")
            }
            if case let .failed(message) = model.debriefState {
                // Debrief specifically failed (session itself is fine).
                // Inline the message under the status so the learner isn't
                // blocked from starting the next session.
                Text("Session summary: \(message)")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("talk-debrief-error")
            }
            Spacer()
            primaryButton
                .padding(.horizontal)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Talk")
    }

    @ViewBuilder
    private var waveformIcon: some View {
        if case .connected = model.state {
            Button {
                Task { await model.interrupt() }
            } label: {
                Image(systemName: statusSymbol)
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("talk-interrupt")
            .accessibilityLabel("Interrupt the tutor")
            .accessibilityHint("Cancels the tutor's current response so you can speak.")
        } else {
            Image(systemName: statusSymbol)
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isSessionActive {
            Button(role: .destructive) {
                Task { await model.end() }
            } label: {
                Label("End session", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("talk-end")
        } else {
            Button {
                Task { await model.start() }
            } label: {
                Label(model.pendingIntent.startButtonTitle, systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.state.isBusy)
            .accessibilityIdentifier("talk-start")
        }
    }

    private var isSessionActive: Bool {
        switch model.state {
        case .requestingSession, .connecting, .connected: return true
        case .idle, .failed, .ended: return false
        }
    }

    private var statusTitle: String {
        switch model.state {
        case .idle: return model.pendingIntent.prompt
        case .requestingSession: return "Preparing your session…"
        case .connecting: return "Connecting to your tutor…"
        case .connected: return "Connected — start speaking"
        case .failed: return "Session couldn't start"
        case .ended: return "Session ended"
        }
    }

    private var statusSymbol: String {
        switch model.state {
        case .idle, .ended: return "mic.circle"
        case .requestingSession, .connecting: return "waveform.circle"
        case .connected: return "waveform.circle.fill"
        case .failed: return "exclamationmark.circle"
        }
    }
}
#endif
