import Foundation
import VoxaRealtime

/// Backend-backed implementation of `RealtimeSessionService` for
/// `POST /api/realtime/session`. Requires an authenticated app session: the
/// caller's access token is sent as a bearer token.
public struct VoxaBackendRealtimeSessionService: RealtimeSessionService {
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

    public func createSession(
        _ settings: RealtimeCoachingSettings,
        accessToken: String
    ) async throws -> RealtimeSessionCredential {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/realtime/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")
        request.httpBody = try JSONEncoder().encode(
            RealtimeSessionRequestDTO(
                coachingMode: settings.coachingMode,
                proficiencyBand: settings.proficiencyBand,
                targetLanguage: settings.targetLanguage
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RealtimeSessionError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw RealtimeSessionError.transport
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }
        do {
            return try Self.decoder.decode(RealtimeSessionResponseDTO.self, from: data).toCredential()
        } catch {
            throw RealtimeSessionError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> RealtimeSessionError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch (status, payload?.code) {
        case (401, _):
            return .appSessionRequired
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
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported ISO-8601 date: \(raw)")
        }
        return decoder
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
