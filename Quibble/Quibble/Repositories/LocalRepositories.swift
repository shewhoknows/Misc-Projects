import Foundation

final class LocalTopicRepository: TopicRepositoryProtocol {
    func fetchTopics() async throws -> [Topic] {
        QuestionBank.topics
    }
}

final class LocalQuestionRepository: QuestionRepositoryProtocol {
    func fetchQuestions(topicID: String, count: Int) async throws -> [Question] {
        Array(QuestionBank.questions(for: topicID).shuffled().prefix(count))
    }

    func fetchQuestions(questionIDs: [String]) async throws -> [Question] {
        let lookup = Dictionary(uniqueKeysWithValues: QuestionBank.all.map { ($0.id, $0) })
        return questionIDs.compactMap { lookup[$0] }
    }
}

final class LocalProfileRepository: ProfileRepositoryProtocol {
    func currentProfile(localProfile: PlayerProfile) async throws -> UserProfile {
        UserProfile(id: localProfile.appleUserID ?? "guest",
                    username: localProfile.name.lowercased().replacingOccurrences(of: " ", with: "_"),
                    displayName: localProfile.name,
                    avatarSeed: localProfile.colorName,
                    totalXP: localProfile.xp,
                    currentStreak: localProfile.dailyStreak,
                    createdAt: nil,
                    updatedAt: nil)
    }

    func createProfile(username: String, displayName: String, avatarSeed: String) async throws -> UserProfile {
        let cleaned = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ServiceError.friendly("Pick a username first.") }
        return UserProfile(id: UUID().uuidString,
                           username: cleaned,
                           displayName: displayName,
                           avatarSeed: avatarSeed,
                           totalXP: 0,
                           currentStreak: 0,
                           createdAt: Date(),
                           updatedAt: Date())
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        profile
    }
}

final class LocalMatchRepository: MatchRepositoryProtocol {
    private var matches: [MatchResult] = []

    func findWaitingMatch(topicID: String, excluding userID: String, matchType: String) async throws -> OnlineMatch? {
        matches.first { result in
            result.match.topicID == topicID
                && result.match.status == .waiting
                && result.match.matchType == matchType
                && result.match.createdBy != userID
        }?.match
    }

    func createMatch(topicID: String, questionIDs: [String], userID: String, matchType: String) async throws -> OnlineMatch {
        OnlineMatch(id: UUID().uuidString,
                    topicID: topicID,
                    matchType: matchType,
                    status: .waiting,
                    createdBy: userID,
                    winnerID: nil,
                    createdAt: Date(),
                    completedAt: nil)
    }

    func joinMatch(_ matchID: String, userID: String) async throws -> OnlineMatch {
        OnlineMatch(id: matchID,
                    topicID: "mixed",
                    matchType: "async",
                    status: .inProgress,
                    createdBy: nil,
                    winnerID: nil,
                           createdAt: Date(),
                           completedAt: nil)
    }

    func questionIDs(for matchID: String) async throws -> [String] {
        []
    }

    func submitResult(matchID: String, userID: String, answers: [AnswerRecord], topicID: String) async throws -> MatchResult {
        let score = answers.map(\.points).reduce(0, +)
        let correct = answers.filter(\.isCorrect).count
        let player = MatchPlayer(id: UUID().uuidString,
                                 matchID: matchID,
                                 userID: userID,
                                 playerSlot: 1,
                                 score: score,
                                 correctCount: correct,
                                 avgAnswerMS: averageMS(answers),
                                 bestStreak: bestStreak(answers),
                                 xpGained: 60,
                                 completedAt: Date())
        let match = OnlineMatch(id: matchID,
                                topicID: topicID,
                                matchType: "async",
                                status: .waiting,
                                createdBy: userID,
                                winnerID: nil,
                                createdAt: Date(),
                                completedAt: nil)
        let result = MatchResult(id: matchID,
                                 match: match,
                                 player: player,
                                 opponent: nil,
                                 answers: answers.map { answer in
                                     PlayerAnswer(id: UUID().uuidString,
                                                  matchID: matchID,
                                                  userID: userID,
                                                  questionID: answer.questionID,
                                                  selectedOption: optionLetter(answer.chosenIndex),
                                                  isCorrect: answer.isCorrect,
                                                  answerMS: Int(answer.timeTaken * 1000),
                                                  points: answer.points)
                                 })
        matches.insert(result, at: 0)
        return result
    }

    func matchHistory(userID: String) async throws -> [MatchResult] {
        matches.filter { $0.player.userID == userID || $0.opponent?.userID == userID }
    }

    private func optionLetter(_ index: Int?) -> String? {
        guard let index else { return nil }
        return ["A", "B", "C", "D"][safe: index]
    }

    private func averageMS(_ answers: [AnswerRecord]) -> Int? {
        guard !answers.isEmpty else { return nil }
        return Int((answers.map(\.timeTaken).reduce(0, +) / Double(answers.count)) * 1000)
    }

    private func bestStreak(_ answers: [AnswerRecord]) -> Int {
        var best = 0
        var run = 0
        for answer in answers {
            run = answer.isCorrect ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }
}

final class LocalLeaderboardRepository: LeaderboardRepositoryProtocol {
    func topicLeaderboard(topicID: String, limit: Int) async throws -> [LeaderboardEntry] {
        Array(MockData.leaderboardSeeds.prefix(limit).enumerated().map { index, seed in
            LeaderboardEntry(id: seed.name,
                             name: seed.name,
                             colorName: seed.colorName,
                             xp: seed.baseXP - index * 37,
                             isPlayer: false)
        })
    }

    func dailyLeaderboard(dateKey: String, limit: Int) async throws -> [LeaderboardEntry] {
        try await topicLeaderboard(topicID: "daily", limit: limit)
    }
}

final class LocalDailyChallengeRepository: DailyChallengeRepositoryProtocol {
    func today(userID: String?) async throws -> DailyChallenge {
        DailyChallenge(id: DateKeys.today,
                       dateKey: DateKeys.today,
                       topicID: nil,
                       title: "Daily Challenge",
                       questions: QuestionBank.dailySet(dateKey: DateKeys.today),
                       completedResult: nil)
    }

    func submit(result: DailyChallengeResult) async throws -> DailyChallengeResult {
        result
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

final class LocalFriendRepository: FriendRepositoryProtocol {
    private let block = ServiceError.friendly("Sign in with Apple to use friend codes and live challenges.")

    func ensureFriendCode() async throws -> String { throw block }
    func lookupProfile(friendCode: String) async throws -> PublicFriendProfile { throw block }
    func sendFriendRequest(friendCode: String) async throws -> Friendship { throw block }
    func incomingRequests() async throws -> [Friendship] { throw block }
    func outgoingRequests() async throws -> [Friendship] { throw block }
    func acceptedFriendships() async throws -> [Friendship] { throw block }
    func acceptRequest(_ friendshipID: String) async throws -> Friendship { throw block }
    func declineRequest(_ friendshipID: String) async throws -> Friendship { throw block }
    func cancelRequest(_ friendshipID: String) async throws -> Friendship { throw block }
}

final class LocalLiveDuelInviteRepository: LiveDuelInviteRepositoryProtocol {
    private let block = ServiceError.friendly("Sign in to create or join a live duel room.")

    func createInvite(topicID: String) async throws -> LiveDuelInvite { throw block }
    func joinInvite(code: String) async throws -> JoinedLiveDuelInvite { throw block }
    func resolveTopicSlug(fromUUID uuid: String) async throws -> String { throw block }
}
