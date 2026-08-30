/// The Common European Framework of Reference levels, ordered A1 (beginner) to
/// C2 (mastery).
public enum CEFRLevel: String, CaseIterable, Sendable, Codable, Comparable {
    case a1, a2, b1, b2, c1, c2

    public var displayName: String { rawValue.uppercased() }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: CEFRLevel, rhs: CEFRLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}
