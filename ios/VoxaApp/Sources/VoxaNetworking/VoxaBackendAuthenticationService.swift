import Foundation
import os
import VoxaAuth

/// Backend-backed implementation of `AuthenticationService` for the Voxa
/// app-session endpoints (`POST /api/auth/apple`, `/refresh`, `/logout`).
///
/// The contract is isolated behind the DTOs in `AuthContractDTOs.swift`; this
/// type maps them to and from `VoxaAuth` domain types. It has no default base
/// URL — the app composition layer must supply one, and callers get a clear
/// error if it is missing (see `NotConfiguredAuthenticationService`).
public struct VoxaBackendAuthenticationService: AuthenticationService {
    private static let logger = Logger(subsystem: "com.simonholmes.voxa", category: "authentication")

    private let baseURL: URL
    private let session: URLSession
    private let correlationIDProvider: @Sendable () -> String

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        correlationIDProvider: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.correlationIDProvider = correlationIDProvider
    }

    public func exchange(_ proof: AppleIdentityProof) async throws -> AuthSession {
        let body = SignInWithAppleRequestDTO(
            identityToken: String(decoding: proof.identityToken, as: UTF8.self),
            authorizationCode: String(decoding: proof.authorizationCode, as: UTF8.self),
            nonce: proof.nonce
        )
        let response: AppSessionResponseDTO = try await post("api/auth/apple", body: body)
        return response.toAuthSession()
    }

    public func refresh(_ session: AuthSession) async throws -> AuthSession {
        let response: AppSessionResponseDTO = try await post(
            "api/auth/refresh",
            body: RefreshRequestDTO(refreshToken: session.refreshToken)
        )
        return response.toAuthSession()
    }

    public func invalidate(_ session: AuthSession) async throws {
        let _: LogoutResponseDTO = try await post(
            "api/auth/logout",
            body: LogoutRequestDTO(refreshToken: session.refreshToken)
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let correlationID = correlationIDProvider()
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.httpBody = try JSONEncoder().encode(body)

        Self.logger.info("Auth request started endpoint=\(path, privacy: .public) url=\(request.url?.absoluteString ?? "", privacy: .public) correlationId=\(correlationID, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            Self.logger.error("Auth request transport failure endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            throw AuthenticationServiceError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            Self.logger.error("Auth request returned a non-HTTP response endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public)")
            throw AuthenticationServiceError.transport
        }
        Self.logger.info("Auth response received endpoint=\(path, privacy: .public) status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) correlationId=\(correlationID, privacy: .public)")
        guard (200..<300).contains(http.statusCode) else {
            let error = Self.mapError(status: http.statusCode, data: data)
            let code = (try? JSONDecoder().decode(ApiErrorDTO.self, from: data).code) ?? "unknown"
            Self.logger.error("Auth request rejected endpoint=\(path, privacy: .public) status=\(http.statusCode, privacy: .public) apiCode=\(code, privacy: .public) correlationId=\(correlationID, privacy: .public)")
            throw error
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            Self.logger.error("Auth response decode failure endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw AuthenticationServiceError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> AuthenticationServiceError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch (status, payload?.code) {
        case (401, "apple_identity_invalid"):
            return .invalidAppleIdentity
        case (401, "session_refresh_invalid"), (401, _):
            return .sessionExpired
        case (400, _):
            return .validation(payload?.message ?? "The request was invalid.")
        default:
            return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ISO-8601 date: \(raw)"
            )
        }
        return decoder
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
