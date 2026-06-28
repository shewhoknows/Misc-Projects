import Foundation

enum OnlineMode: String, Codable, Equatable {
    case localDemo
    case remote
    case live
    case offlineFallback
}

enum ServiceStatus: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct UserProfile: Identifiable, Codable, Equatable {
    let id: String
    var username: String
    var displayName: String
    var avatarSeed: String
    var totalXP: Int
    var currentStreak: Int
    var friendCode: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct AnswerOption: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let isCorrect: Bool?
}

enum OnlineMatchStatus: String, Codable, Equatable {
    case waiting
    case inProgress = "in_progress"
    case completed
    case botFallback = "bot_fallback"
}

struct OnlineMatch: Identifiable, Codable, Equatable {
    let id: String
    let topicID: String
    var matchType: String
    var status: OnlineMatchStatus
    var createdBy: String?
    var winnerID: String?
    var createdAt: Date?
    var completedAt: Date?
}

struct MatchPlayer: Identifiable, Codable, Equatable {
    let id: String
    let matchID: String
    let userID: String
    let playerSlot: Int
    var score: Int
    var correctCount: Int
    var avgAnswerMS: Int?
    var bestStreak: Int
    var xpGained: Int
    var completedAt: Date?
}

struct PlayerAnswer: Identifiable, Codable, Equatable {
    let id: String
    let matchID: String
    let userID: String
    let questionID: String
    let selectedOption: String?
    let isCorrect: Bool
    let answerMS: Int
    let points: Int
}

struct MatchResult: Identifiable, Codable, Equatable {
    let id: String
    let match: OnlineMatch
    let player: MatchPlayer
    let opponent: MatchPlayer?
    let answers: [PlayerAnswer]

    var isWaitingForOpponent: Bool {
        match.status == .waiting || opponent?.completedAt == nil
    }
}

struct TopicUserStats: Identifiable, Codable, Equatable {
    let id: String
    let userID: String
    let topicID: String
    var xp: Int
    var wins: Int
    var losses: Int
    var matchesPlayed: Int
    var bestScore: Int
    var correctAnswers: Int
    var totalAnswers: Int
}

struct DailyChallenge: Identifiable, Codable, Equatable {
    let id: String
    let dateKey: String
    let topicID: String?
    let title: String
    let questions: [Question]
    var completedResult: DailyChallengeResult?
}

struct DailyChallengeResult: Identifiable, Codable, Equatable {
    let id: String
    let challengeID: String
    let userID: String
    let score: Int
    let correctCount: Int
    let xpGained: Int
    let completedAt: Date
}

struct OnlineMatchDraft: Equatable {
    let topic: Topic
    let questions: [Question]
    let match: OnlineMatch?
    let opponent: Bot?
    let mode: OnlineMode

    var usesBotFallback: Bool { opponent != nil || (mode != .remote && mode != .live) }
}

// MARK: - Friend codes & friendships

struct PublicFriendProfile: Identifiable, Codable, Equatable {
    let id: String
    let username: String
    let displayName: String
    let avatarSeed: String
}

enum FriendshipStatus: String, Codable, Equatable, CaseIterable {
    case pending
    case accepted
    case declined
    case cancelled
}

struct Friendship: Identifiable, Codable, Equatable {
    let id: String
    let requesterID: String
    let addresseeID: String
    let status: FriendshipStatus
    let createdAt: Date?
    let respondedAt: Date?
    var otherProfile: PublicFriendProfile?

    func otherUserID(for currentUserID: String) -> String {
        requesterID == currentUserID ? addresseeID : requesterID
    }

    var isIncoming: Bool { status == .pending }
}

// MARK: - Live duel invites

struct LiveDuelInvite: Identifiable, Codable, Equatable {
    let inviteID: String
    let matchID: String
    let joinCode: String
    let topicID: String
    let expiresAt: Date
    var id: String { inviteID }
}

struct JoinedLiveDuelInvite: Identifiable, Codable, Equatable {
    let inviteID: String
    let matchID: String
    let hostID: String
    let topicID: String
    var id: String { inviteID }
}

/// Held after createLiveRoom succeeds so the host can show the join code
/// before calling startHostLiveRoom() to begin the match.
struct PendingLiveRoom {
    let invite: LiveDuelInvite
    let questions: [Question]
    let topic: Topic
}
