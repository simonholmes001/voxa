---
"voxa": patch
---

Fix `VoxaBackendLanguageProfilesService` URL construction so a language key that contains `/` (e.g. `zh/Hant`) percent-encodes to a single path segment (`zh%2FHant`) instead of being split across multiple segments — the previous `.urlPathAllowed` set treats `/` as safe, and `URL.appendingPathComponent` additionally re-encoded pre-encoded `%` to `%25`, double-encoding the segment. Path parameters are now encoded with a `.urlPathAllowed` minus `/` set, and the request URL is built via `URL(string:relativeTo:)` which preserves the caller's percent-encoding. Applies to both DELETE and `POST /language-profiles/{languageKey}/select`.
