import Foundation
import VoxaProfiles

/// Backend-backed `LanguageProfilesService` for `GET /api/language-profiles`
/// and `POST /api/language-profiles/{languageKey}/select`. Requires an
/// authenticated app session (access token is sent as a bearer token).
public struct VoxaBackendLanguageProfilesService: LanguageProfilesService {
    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String
    private let accessTokenProvider: @MainActor @Sendable () -> String?

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        accessTokenProvider: @escaping @MainActor @Sendable () -> String?
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
        self.accessTokenProvider = accessTokenProvider
    }

    public func list() async throws -> LanguageProfileList {
        let token = try await requireToken()
        let dto: LanguageProfilesListResponseDTO = try await send(
            path: "api/language-profiles", method: "GET", body: nil, accessToken: token
        )
        let profiles = try dto.profiles.map { try $0.toLanguageProfile() }
        return LanguageProfileList(activeLanguageKey: dto.activeLanguageKey, profiles: profiles)
    }

    public func selectActive(languageKey: String) async throws -> String {
        let token = try await requireToken()
        let encoded = languageKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? languageKey
        let dto: SelectLanguageResponseDTO = try await send(
            path: "api/language-profiles/\(encoded)/select", method: "POST", body: Data("{}".utf8), accessToken: token
        )
        return dto.activeLanguageKey
    }

    private func requireToken() async throws -> String {
        guard let token = await accessTokenProvider() else {
            throw LanguageProfilesError.authenticationRequired
        }
        return token
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LanguageProfilesError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw LanguageProfilesError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LanguageProfilesError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> LanguageProfilesError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch (status, payload?.code) {
        case (401, _):
            return .authenticationRequired
        case (404, _):
            return .unknownLanguage
        case (409, _):
            return .versionConflict
        default:
            return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }
}
