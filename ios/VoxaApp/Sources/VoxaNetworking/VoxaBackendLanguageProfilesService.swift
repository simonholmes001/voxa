import Foundation
import os
import VoxaProfiles

/// Backend-backed `LanguageProfilesService` for `GET /api/language-profiles`
/// and `POST /api/language-profiles/{languageKey}/select`. Requires an
/// authenticated app session (access token is sent as a bearer token).
public struct VoxaBackendLanguageProfilesService: LanguageProfilesService {
    private static let logger = Logger(subsystem: "com.simonholmes.voxa", category: "language-profiles")

    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String
    private let accessTokenProvider: @MainActor @Sendable () -> String?
    private let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString },
        accessTokenProvider: @escaping @MainActor @Sendable () -> String?,
        requestTimeout: TimeInterval = 15
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
        self.accessTokenProvider = accessTokenProvider
        self.requestTimeout = requestTimeout
    }

    public func list() async throws -> LanguageProfileList {
        let token = try await requireToken()
        let dto: LanguageProfilesListResponseDTO = try await send(
            path: "api/language-profiles", method: "GET", body: nil, accessToken: token
        )
        let profiles: [LanguageProfile]
        do {
            profiles = try dto.profiles.map { try $0.toLanguageProfile() }
        } catch {
            Self.logger.error("Profile response mapping failure endpoint=api/language-profiles error=\(String(describing: error), privacy: .public)")
            throw LanguageProfilesError.transport
        }
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
            Self.logger.error("Profile request blocked: no access token")
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
        request.timeoutInterval = requestTimeout
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
        let correlationID = request.value(forHTTPHeaderField: "X-Correlation-Id") ?? "missing"
        Self.logger.info("Profile request started method=\(method, privacy: .public) endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public)")
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            Self.logger.error("Profile request transport failure endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            throw LanguageProfilesError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("Profile request returned non-HTTP response endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public)")
            throw LanguageProfilesError.transport
        }
        Self.logger.info("Profile response received endpoint=\(path, privacy: .public) status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) correlationId=\(correlationID, privacy: .public)")
        guard (200..<300).contains(http.statusCode) else {
            let error = Self.mapError(status: http.statusCode, data: data)
            Self.logger.error("Profile request rejected endpoint=\(path, privacy: .public) status=\(http.statusCode, privacy: .public) error=\(String(describing: error), privacy: .public) correlationId=\(correlationID, privacy: .public)")
            throw error
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            Self.logger.error("Profile response decode failure endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public) error=\(String(describing: error), privacy: .public)")
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
