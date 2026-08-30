import Foundation
import VoxaAuth

/// Backend-backed implementation of `AuthenticationService` for the Voxa
/// app-session endpoints (`POST /api/auth/apple`, `/refresh`, `/logout`).
///
/// The contract is isolated behind the DTOs in `AuthContractDTOs.swift`; this
/// type maps them to and from `VoxaAuth` domain types. It has no default base
/// URL — the app composition layer must supply one, and callers get a clear
/// error if it is missing (see `NotConfiguredAuthenticationService`).
public struct VoxaBackendAuthenticationService: AuthenticationService {
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
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthenticationServiceError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationServiceError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
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
