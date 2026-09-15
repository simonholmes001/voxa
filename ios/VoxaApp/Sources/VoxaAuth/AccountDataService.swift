import Foundation

public protocol AccountDataService: Sendable {
    func exportAccountData(_ session: AuthSession) async throws -> AccountDataExportFile
    func deleteAccount(_ session: AuthSession) async throws -> AccountDeletionResult
}

public struct AccountDataExportFile: Sendable, Equatable {
    public let filename: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }
}

public struct AccountDeletionResult: Sendable, Equatable {
    public let deleted: Bool
    public let deletedLanguageProfileCount: Int

    public init(deleted: Bool, deletedLanguageProfileCount: Int) {
        self.deleted = deleted
        self.deletedLanguageProfileCount = deletedLanguageProfileCount
    }
}

public enum AccountDataServiceError: Error, Equatable {
    case unavailable
    case notConfigured(String)
    case authenticationRequired
    case validation(String)
    case server(code: Int, message: String)
    case transport
}

public struct UnavailableAccountDataService: AccountDataService {
    public init() {}

    public func exportAccountData(_ session: AuthSession) async throws -> AccountDataExportFile {
        throw AccountDataServiceError.unavailable
    }

    public func deleteAccount(_ session: AuthSession) async throws -> AccountDeletionResult {
        throw AccountDataServiceError.unavailable
    }
}

public struct NotConfiguredAccountDataService: AccountDataService {
    private let reason: String

    public init(reason: String = "The backend base URL (VOXA_API_BASE_URL) is not configured.") {
        self.reason = reason
    }

    public func exportAccountData(_ session: AuthSession) async throws -> AccountDataExportFile {
        throw AccountDataServiceError.notConfigured(reason)
    }

    public func deleteAccount(_ session: AuthSession) async throws -> AccountDeletionResult {
        throw AccountDataServiceError.notConfigured(reason)
    }
}
