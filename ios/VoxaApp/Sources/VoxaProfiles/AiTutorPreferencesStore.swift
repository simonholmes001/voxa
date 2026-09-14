import Foundation
import VoxaRealtime

@MainActor
public protocol AiTutorPreferencesStore: AnyObject {
    func preferences(for languageKey: String) -> AiTutorPreferences
    func save(_ preferences: AiTutorPreferences, for languageKey: String)
}

public final class UserDefaultsAiTutorPreferencesStore: AiTutorPreferencesStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func preferences(for languageKey: String) -> AiTutorPreferences {
        guard let data = defaults.data(forKey: key(for: languageKey)),
              let preferences = try? decoder.decode(AiTutorPreferences.self, from: data)
        else { return .default }
        return preferences
    }

    public func save(_ preferences: AiTutorPreferences, for languageKey: String) {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: key(for: languageKey))
    }

    private func key(for languageKey: String) -> String {
        "voxa.aiTutorPreferences.\(languageKey)"
    }
}

public final class InMemoryAiTutorPreferencesStore: AiTutorPreferencesStore {
    private var values: [String: AiTutorPreferences]

    public init(values: [String: AiTutorPreferences] = [:]) {
        self.values = values
    }

    public func preferences(for languageKey: String) -> AiTutorPreferences {
        values[languageKey] ?? .default
    }

    public func save(_ preferences: AiTutorPreferences, for languageKey: String) {
        values[languageKey] = preferences
    }
}
