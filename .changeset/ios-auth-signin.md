---
"voxa": minor
---

Add the iOS Sign in with Apple UI and secure session lifecycle (`VoxaAuth`): a Sign in with Apple screen, an `AuthViewModel` handling restore/exchange/refresh/sign-out, and Keychain-backed token storage. `RootView` now gates the navigation shell behind authentication. The backend token exchange stays behind an injectable `AuthenticationService` seam (backend contract owned by #17 backend / #14).
