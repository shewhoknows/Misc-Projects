import Foundation

// MARK: - Mascot

enum MascotState: String, Codable, CaseIterable {
    case neutral, happy, thinking, surprised, competitive
    case proud, confused, sleepy, excited
}

// MARK: - Topics & questions

enum Difficulty: String, Codable, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

struct Topic: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let symbol: String        // SF Symbol used as the mascot's small accessory
    let colorName: String
    let mascot: MascotState
    let blurb: String
}

struct Question: Identifiable, Codable, Equatable {
    let id: String
    let topicID: String
    let difficulty: Difficulty
    let text: String
    let options: [String]
    let correctIndex: Int
}

// MARK: - Opponents

struct Bot: Identifiable, Equatable {
    let id: String
    let name: String
    let colorName: String
    let mascot: MascotState
    let accuracy: Double      // chance of a correct answer per question
    let minTime: Double       // fastest answer in seconds
    let maxTime: Double       // slowest answer in seconds
    let tagline: String
}

struct Friend: Identifiable, Equatable {
    let id: String
    let name: String
    let colorName: String
    let level: Int
    let status: String
}

// MARK: - Matches

enum MatchMode: String, Codable {
    case quick, topic, daily, friend
}

enum MatchOutcome: String, Codable {
    case win, loss, draw
}

struct AnswerRecord: Codable, Equatable, Identifiable {
    let questionID: String
    let questionText: String
    let options: [String]
    let correctIndex: Int
    let chosenIndex: Int?     // nil means the clock ran out
    let timeTaken: Double
    let points: Int
    let speedBonus: Int
    let streakBonus: Int
    let botCorrect: Bool
    let botPoints: Int

    var id: String { questionID }
    var isCorrect: Bool { chosenIndex == correctIndex }
    var timedOut: Bool { chosenIndex == nil }
}

struct MatchRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let date: Date
    let mode: MatchMode
    let topicID: String       // "mixed" for the daily challenge
    let topicName: String
    let opponentName: String
    let opponentColorName: String
    let yourScore: Int
    let opponentScore: Int
    let outcome: MatchOutcome
    let xpEarned: Int
    let answers: [AnswerRecord]

    var correctCount: Int { answers.filter(\.isCorrect).count }
    var isPerfect: Bool { !answers.isEmpty && correctCount == answers.count }
    var averageAnswerTime: Double {
        guard !answers.isEmpty else { return 0 }
        return answers.map(\.timeTaken).reduce(0, +) / Double(answers.count)
    }
}

// MARK: - Player

struct PlayerProfile: Codable, Equatable {
    var name: String = "You"
    var appleUserID: String?
    var appleEmail: String?
    var colorName: String = "yellow"
    var xp: Int = 0
    var weeklyXP: Int = 0
    var weekKey: String = ""
    var favoriteTopicIDs: [String] = []
    var dailyStreak: Int = 0
    var bestDailyStreak: Int = 0
    var lastDailyDate: String = ""        // "yyyy-MM-dd" of last completed daily
    var unlockedAchievements: [String] = []
    var challengesSent: Int = 0
    var onboarded: Bool = false
    var hapticsOn: Bool = true

    static let xpPerLevel = 500

    var level: Int { xp / PlayerProfile.xpPerLevel + 1 }
    var xpIntoLevel: Int { xp % PlayerProfile.xpPerLevel }
    var levelProgress: Double { Double(xpIntoLevel) / Double(PlayerProfile.xpPerLevel) }
    var isSignedInWithApple: Bool { appleUserID != nil }
}

// MARK: - Social mocks

struct PendingChallenge: Codable, Equatable, Identifiable {
    let id: UUID
    let friendName: String
    let friendColorName: String
    let topicID: String
    let topicName: String
    let date: Date
}

struct LeaderboardEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let colorName: String
    let xp: Int
    let isPlayer: Bool
}

// MARK: - Achievements

struct Achievement: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
}

// MARK: - Match setup

struct MatchSetup: Identifiable, Equatable {
    let id: UUID
    let mode: MatchMode
    let topic: Topic?         // nil for the mixed daily challenge
    let opponent: Bot
    let questions: [Question]
    var onlineMatchID: String? = nil
    var onlineMode: OnlineMode = .localDemo
    var onlineCreatedBy: String? = nil

    var topicID: String { topic?.id ?? "mixed" }
    var topicName: String { topic?.name ?? "Mixed Bag" }
    var isLive: Bool { onlineMode == .live }
}

// MARK: - Deterministic RNG (used so the daily challenge is the same all day)

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension String {
    /// Stable 64-bit hash (Swift's `hashValue` is randomized per launch).
    var stableHash: UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }

    /// Normalize a friend code or join code: uppercase, trim, keep only the
    /// valid alphabet (no O/0/I/1).
    var normalizedCode: String {
        uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }
    }
}

// MARK: - Date keys

enum DateKeys {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func key(for date: Date) -> String {
        formatter.string(from: date)
    }

    static var today: String { key(for: Date()) }

    static var yesterday: String {
        key(for: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    static var weekKey: String {
        let cal = Calendar.current
        let week = cal.component(.weekOfYear, from: Date())
        let year = cal.component(.yearForWeekOfYear, from: Date())
        return "\(year)-W\(week)"
    }
}
