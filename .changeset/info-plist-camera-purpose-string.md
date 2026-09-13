---
"voxa": patch
---

Adds `NSCameraUsageDescription` to `Info.plist` so Apple's post-upload validation stops rejecting builds with ITMS-90683.

voxa never uses the camera, but the WebRTC library it links for real-time voice references `AVCaptureDevice` at the API level. Apple requires a purpose string for any camera-touching linked code even when the app never calls it. The purpose string explains that context honestly to the reader.

No behaviour change — the string is only surfaced if voxa ever prompts for camera access (it doesn't).
