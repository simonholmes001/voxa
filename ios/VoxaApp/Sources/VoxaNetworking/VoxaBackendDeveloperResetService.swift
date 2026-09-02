import Foundation

public protocol DeveloperResetService: Sendable {
    func resetLearnerState(accessToken: String) async throws
}

public enum DeveloperResetServiceError: Error, Equatable {
    case unavailable
    case authenticationRequired
    case transport
    case server(code: Int, message: String)
}

public struct UnavailableDeveloperResetService: DeveloperResetService {
    public init() {}

    public func resetLearnerState(accessToken: String) async throws {
        throw DeveloperResetServiceError.unavailable
    }
}

public struct VoxaBackendDeveloperResetService: DeveloperResetService {
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

    public func resetLearnerState(accessToken: String) async throws {
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeveloperResetServiceError.authenticationRequired
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/dev/learner-state"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(correlationIDProvider(), forHTTPHeaderField: "X-Correlation-Id")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DeveloperResetServiceError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeveloperResetServiceError.transport
        }

        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }

        do {
            let reset = try JSONDecoder().decode(DevResetResponseDTO.self, from: data)
            guard reset.deleted else {
                throw DeveloperResetServiceError.server(code: http.statusCode, message: "Reset was not applied.")
            }
        } catch let error as DeveloperResetServiceError {
            throw error
        } catch {
            throw DeveloperResetServiceError.transport
        }
    }

    private static func mapError(status: Int, data: Data) -> DeveloperResetServiceError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch (status, payload?.code) {
        case (401, _):
            return .authenticationRequired
        case (404, "dev_reset_unavailable"):
            return .unavailable
        default:
            return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }
}
