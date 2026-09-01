# WebRTC Realtime Transport - Device Testing Guide

## Prerequisites

1. **Backend Configuration Required**
   - Build Voxa with `VOXA_API_BASE_URL` pointing to deployed Function App
   - Without this, transport falls back to `UnavailableRealtimeTransport`

2. **Microphone Permission**
   - The app will request microphone permission on first Talk session start
   - Required for local audio track

3. **Active Internet Connection**
   - WebRTC needs to reach OpenAI Realtime API
   - Uses STUN server for ICE candidate gathering

## Test Scenarios

### ✅ Happy Path: Complete Talk Session

1. Sign in to the app
2. Complete onboarding (or have existing profile)
3. Navigate to Talk screen
4. Tap "Start" or equivalent button
5. Grant microphone permission if prompted
6. Observe state transitions:
   - `idle` → `requestingSession` → `connecting` → `connected`
7. Speak into the microphone
8. Verify you can hear tutor's voice response
9. Tap "End" or equivalent button
10. Observe state transition to `ended`

**Expected:** Full voice conversation with OpenAI Realtime tutor

### ❌ No Backend Configuration

1. Build app without `VOXA_API_BASE_URL` setting
2. Navigate to Talk screen
3. Tap "Start"

**Expected:** Immediate failure with message:
"Voice sessions aren't configured for this build yet."

### ❌ Microphone Permission Denied

1. Deny microphone permission when prompted (or deny in Settings beforehand)
2. Attempt to start Talk session

**Expected:** State transitions to `.failed` with message:
"Microphone access is required to talk with your tutor."

### ❌ Expired Session Credential

1. Mock/modify backend to return past `expiresAt` timestamp
2. Attempt to start Talk session

**Expected:** Connection fails with message:
"Session credential has expired"

### ❌ Network Failure

1. Enable airplane mode
2. Attempt to start Talk session

**Expected:** State transitions to `.failed` after timeout

### ⚠️ Audio Interruption Handling

1. Start Talk session successfully
2. Receive phone call or trigger Siri
3. Observe audio session interruption behavior

**Expected (current implementation):** Session may disconnect on interruption.
**Follow-up work needed:** Handle interruptions gracefully, reconnect after interruption ends.

### ⚠️ Audio Route Changes

1. Start Talk session with built-in speaker
2. Connect Bluetooth headphones mid-session
3. Observe audio route change

**Expected (current implementation):** Audio should follow route change.
**Follow-up work needed:** Verify seamless route transitions without dropouts.

## Known Limitations (Deferred to Follow-up)

### Not Implemented Yet

- **Transcripts:** No UI for displaying real-time transcripts of user/tutor speech
- **Session Summaries:** No post-session summary or lesson report
- **Analytics:** No usage tracking or performance metrics
- **Reconnection:** Connection drops are terminal; no automatic retry
- **Advanced Error Handling:** Generic error messages for most failures
- **Session Persistence:** Cannot resume interrupted sessions

### Follow-up Issues

- #24 (full Talk UX): transcripts, summaries, advanced settings
- Audio interruption recovery
- Network reconnection logic
- Better error diagnostics for debugging

## Device/Platform Testing Matrix

| Device | iOS Version | Mic Type | Expected Result |
|--------|-------------|----------|-----------------|
| iPhone 14 Pro | iOS 17.0+ | Built-in | ✅ Full audio |
| iPhone SE | iOS 17.0+ | Built-in | ✅ Full audio |
| iPad mini | iPadOS 17.0+ | Built-in | ✅ Full audio |
| iPhone with AirPods | iOS 17.0+ | Bluetooth | ⚠️ Verify route |
| iPad with wired headphones | iPadOS 17.0+ | Wired | ⚠️ Verify route |

## Debugging Tips

### Enable Verbose Logging

1. Add breakpoints in `WebRTCRealtimeTransport.swift`:
   - Line ~45: After SDP offer creation
   - Line ~92: After remote description set
   - Line ~112: On disconnect

2. Check Xcode console for WebRTC internal logs (RTCPeerConnection lifecycle)

### Common Issues

**Problem:** Build fails with WebRTC dependency errors
**Solution:** Ensure `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="safe.bareRepository" GIT_CONFIG_VALUE_0="all"` is set when resolving packages

**Problem:** Transport immediately fails with "not configured"
**Solution:** Verify `VOXA_API_BASE_URL` is set in Xcode build settings

**Problem:** State stuck at "connecting"
**Solution:** Check network connectivity, verify backend returns valid clientSecret

**Problem:** No audio heard from tutor
**Solution:** Check AVAudioSession category, verify peer connection `ontrack` event fires

## Implementation Notes

### Architecture

- **Isolation:** WebRTC logic is isolated behind `RealtimeTransport` protocol
- **Testability:** ViewModel tests use `FakeRealtimeTransport`, real transport is tested on device
- **Platform:** iOS-specific AVAudioSession code is guarded with `#if os(iOS)`
- **Thread Safety:** Transport marked `@unchecked Sendable` (peer connection requires careful state management)

### OpenAI Realtime API Integration

- **Authentication:** Uses backend-issued `clientSecret` as bearer token
- **SDP Exchange:** Posts local SDP offer to `https://api.openai.com/v1/realtime/calls`
  as multipart form data with `sdp` and `session` parts; success is validated
  against the documented `201 Created`/2xx SDP answer path.
- **WebRTC Mode:** Ephemeral token approach (not unified interface)
- **Session Config:** Uses the backend-returned `model` and `reasoningEffort`
  from `POST /api/realtime/session` rather than hardcoding model IDs in the
  iOS transport.
- **Connection Readiness:** Talk only reports connected after WebRTC ICE reaches
  connected/completed; failure and timeout paths tear down local resources.
- **Data Channel:** Created for Realtime events (not used in current scope)

### WebRTC Dependency

- **Package:** stasel/WebRTC 152.0.0
- **License:** BSD 3-Clause (permissive)
- **Size:** ~42MB xcframework (~15-20MB per architecture after App Store thinning)
- **Source:** Community binary built from official Google WebRTC sources
- **Limitation:** Binary-only target, no source code audit possible

## Next Steps After Device Testing

1. Verify all happy-path scenarios work on physical devices
2. Test with various network conditions (WiFi, cellular, poor signal)
3. Test audio route changes (Bluetooth connect/disconnect)
4. Test interruptions (calls, Siri, alarms)
5. Document any failures or unexpected behavior
6. File follow-up issues for:
   - Reconnection logic
   - Interruption handling
   - Transcript display
   - Session summaries
