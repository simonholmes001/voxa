import Foundation
import os
import VoxaAuth

public struct VoxaBackendAccountDataService: AccountDataService {
    private static let logger = Logger(subsystem: "com.simonholmes.voxa", category: "account-data")

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

    public func exportAccountData(_ session: AuthSession) async throws -> AccountDataExportFile {
        let data = try await request(
            "api/account/export",
            method: "GET",
            accessToken: session.accessToken)
        return AccountDataExportFile(
            filename: "voxa-account-data-\(Self.filenameDate()).json",
            data: data)
    }

    public func deleteAccount(_ session: AuthSession) async throws -> AccountDeletionResult {
        let data = try await request(
            "api/account",
            method: "DELETE",
            accessToken: session.accessToken)
        do {
            let response = try JSONDecoder().decode(AccountDeletionResponseDTO.self, from: data)
            return AccountDeletionResult(
                deleted: response.deleted,
                deletedLanguageProfileCount: response.deletedLanguageProfileCount)
        } catch {
            Self.logger.error("Account deletion response decode failure error=\(String(describing: error), privacy: .public)")
            throw AccountDataServiceError.transport
        }
    }

    private func request(
        _ path: String,
        method: String,
        accessToken: String
    ) async throws -> Data {
        guard !accessToken.isEmpty else {
            throw AccountDataServiceError.authenticationRequired
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let correlationID = correlationIDProvider()
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")

        Self.logger.info("Account data request started method=\(method, privacy: .public) endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            Self.logger.error("Account data transport failure endpoint=\(path, privacy: .public) correlationId=\(correlationID, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            throw AccountDataServiceError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw AccountDataServiceError.transport
        }

        Self.logger.info("Account data response received endpoint=\(path, privacy: .public) status=\(http.statusCode, privacy: .public) bytes=\(data.count, privacy: .public) correlationId=\(correlationID, privacy: .public)")
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data)
        }

        return data
    }

    private static func mapError(status: Int, data: Data) -> AccountDataServiceError {
        let payload = try? JSONDecoder().decode(ApiErrorDTO.self, from: data)
        switch (status, payload?.code) {
        case (401, _):
            return .authenticationRequired
        case (400, _):
            return .validation(payload?.message ?? "The request was invalid.")
        default:
            return .server(code: status, message: payload?.message ?? "The server returned an error.")
        }
    }

    private static func filenameDate() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
