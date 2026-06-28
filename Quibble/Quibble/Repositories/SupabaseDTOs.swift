import Foundation

struct SupabaseTopicDTO: Codable {
    let id: String
    let slug: String
    let title: String
    let subtitle: String?
    let description: String?
    let colorKey: String?
    let iconAssetName: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, subtitle, description
        case colorKey = "color_key"
        case iconAssetName = "icon_asset_name"
    }

    var topic: Topic {
        Topic(id: slug,
              name: title,
              symbol: iconAssetName ?? "sparkles",
              colorName: colorKey ?? "yellow",
              mascot: .happy,
              blurb: subtitle ?? description ?? "")
    }
}

struct SupabaseQuestionDTO: Codable {
    let id: String
    let topicID: String
    let topicSlug: String?
    let prompt: String
    let optionA: String
    let optionB: String
    let optionC: String
    let optionD: String
    let correctOption: String
    let difficulty: String?
    let topics: SupabaseQuestionTopicDTO?

    enum CodingKeys: String, CodingKey {
        case id, prompt, difficulty, topics
        case topicID = "topic_id"
        case topicSlug = "topic_slug"
        case optionA = "option_a"
        case optionB = "option_b"
        case optionC = "option_c"
        case optionD = "option_d"
        case correctOption = "correct_option"
    }

    var question: Question {
        Question(id: id,
                 topicID: topics?.slug ?? topicSlug ?? topicID,
                 difficulty: Difficulty(rawValue: difficulty?.capitalized ?? "") ?? .easy,
                 text: prompt,
                 options: [optionA, optionB, optionC, optionD],
                 correctIndex: ["A", "B", "C", "D"].firstIndex(of: correctOption) ?? 0)
    }
}

struct SupabaseQuestionTopicDTO: Codable {
    let slug: String
}

struct SupabaseProfileDTO: Codable {
    let id: String
    let username: String?
    let displayName: String?
    let avatarSeed: String?
    let totalXP: Int?
    let currentStreak: Int?
    let friendCode: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
        case totalXP = "total_xp"
        case currentStreak = "current_streak"
        case friendCode = "friend_code"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var userProfile: UserProfile {
        UserProfile(id: id,
                    username: username ?? "player",
                    displayName: displayName ?? username ?? "Player",
                    avatarSeed: avatarSeed ?? "yellow",
                    totalXP: totalXP ?? 0,
                    currentStreak: currentStreak ?? 0,
                    friendCode: friendCode,
                    createdAt: createdAt,
                    updatedAt: updatedAt)
    }
}

struct SupabaseLeaderboardDTO: Codable {
    let id: String
    let userID: String
    let xp: Int
    let bestScore: Int
    let profiles: SupabaseLeaderboardProfileDTO?

    enum CodingKeys: String, CodingKey {
        case id, xp, profiles
        case userID = "user_id"
        case bestScore = "best_score"
    }

    var entry: LeaderboardEntry {
        LeaderboardEntry(id: userID,
                         name: profiles?.displayName ?? profiles?.username ?? "Player",
                         colorName: profiles?.avatarSeed ?? "yellow",
                         xp: max(xp, bestScore),
                         isPlayer: false)
    }
}

struct SupabaseLeaderboardProfileDTO: Codable {
    let username: String?
    let displayName: String?
    let avatarSeed: String?

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
    }
}

struct SupabaseMatchDTO: Codable {
    let id: String
    let topicID: String?
    let matchType: String?
    let status: String
    let createdBy: String?
    let winnerID: String?
    let createdAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case topicID = "topic_id"
        case matchType = "match_type"
        case createdBy = "created_by"
        case winnerID = "winner_id"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    var match: OnlineMatch {
        OnlineMatch(id: id,
                    topicID: topicID ?? "mixed",
                    matchType: matchType ?? "async",
                    status: OnlineMatchStatus(rawValue: status) ?? .waiting,
                    createdBy: createdBy,
                    winnerID: winnerID,
                    createdAt: createdAt,
                    completedAt: completedAt)
    }
}

struct SupabaseMatchPlayerDTO: Codable {
    let id: String
    let matchID: String
    let userID: String
    let playerSlot: Int
    let score: Int?
    let correctCount: Int?
    let avgAnswerMS: Int?
    let bestStreak: Int?
    let xpGained: Int?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, score
        case matchID = "match_id"
        case userID = "user_id"
        case playerSlot = "player_slot"
        case correctCount = "correct_count"
        case avgAnswerMS = "avg_answer_ms"
        case bestStreak = "best_streak"
        case xpGained = "xp_gained"
        case completedAt = "completed_at"
    }

    var player: MatchPlayer {
        MatchPlayer(id: id,
                    matchID: matchID,
                    userID: userID,
                    playerSlot: playerSlot,
                    score: score ?? 0,
                    correctCount: correctCount ?? 0,
                    avgAnswerMS: avgAnswerMS,
                    bestStreak: bestStreak ?? 0,
                    xpGained: xpGained ?? 0,
                    completedAt: completedAt)
    }
}

struct SupabaseDailyChallengeDTO: Codable {
    let id: String
    let challengeDate: String
    let topicID: String?
    let title: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case challengeDate = "challenge_date"
        case topicID = "topic_id"
    }
}

struct SupabaseDailyQuestionDTO: Codable {
    let questionID: String
    let questionIndex: Int

    enum CodingKeys: String, CodingKey {
        case questionID = "question_id"
        case questionIndex = "question_index"
    }
}

struct SupabaseDailyResultDTO: Codable {
    let id: String
    let dailyChallengeID: String
    let userID: String
    let score: Int
    let correctCount: Int
    let xpGained: Int
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, score
        case dailyChallengeID = "daily_challenge_id"
        case userID = "user_id"
        case correctCount = "correct_count"
        case xpGained = "xp_gained"
        case completedAt = "completed_at"
    }

    var result: DailyChallengeResult {
        DailyChallengeResult(id: id,
                             challengeID: dailyChallengeID,
                             userID: userID,
                             score: score,
                             correctCount: correctCount,
                             xpGained: xpGained,
                             completedAt: completedAt)
    }
}

struct SupabasePublicProfileDTO: Codable {
    let id: String
    let username: String?
    let displayName: String?
    let avatarSeed: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
    }

    var profile: PublicFriendProfile {
        PublicFriendProfile(id: id,
                            username: username ?? "player",
                            displayName: displayName ?? username ?? "Player",
                            avatarSeed: avatarSeed ?? "yellow")
    }
}

struct SupabaseFriendshipDTO: Codable {
    let id: String
    let requesterID: String
    let addresseeID: String
    let status: String
    let createdAt: Date?
    let respondedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case requesterID = "requester_id"
        case addresseeID = "addressee_id"
        case createdAt = "created_at"
        case respondedAt = "responded_at"
    }

    var friendship: Friendship {
        Friendship(id: id,
                   requesterID: requesterID,
                   addresseeID: addresseeID,
                   status: FriendshipStatus(rawValue: status) ?? .pending,
                   createdAt: createdAt,
                   respondedAt: respondedAt,
                   otherProfile: nil)
    }
}

struct SupabaseLiveDuelInviteDTO: Codable {
    let inviteID: String
    let matchID: String
    let joinCode: String
    let topicID: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case inviteID = "invite_id"
        case matchID = "match_id"
        case joinCode = "join_code"
        case topicID = "topic_id"
        case expiresAt = "expires_at"
    }

    var invite: LiveDuelInvite {
        LiveDuelInvite(inviteID: inviteID,
                       matchID: matchID,
                       joinCode: joinCode,
                       topicID: topicID,
                       expiresAt: expiresAt)
    }
}

struct SupabaseJoinedLiveDuelInviteDTO: Codable {
    let inviteID: String
    let matchID: String
    let hostID: String
    let topicID: String

    enum CodingKeys: String, CodingKey {
        case inviteID = "invite_id"
        case matchID = "match_id"
        case hostID = "host_id"
        case topicID = "topic_id"
    }

    var joined: JoinedLiveDuelInvite {
        JoinedLiveDuelInvite(inviteID: inviteID,
                             matchID: matchID,
                             hostID: hostID,
                             topicID: topicID)
    }
}
