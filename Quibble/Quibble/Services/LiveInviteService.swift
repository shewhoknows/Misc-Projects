import Foundation

final class LiveInviteService {
    private let repository: LiveDuelInviteRepositoryProtocol
    private let matchRepo: MatchRepositoryProtocol
    private let questionRepo: QuestionRepositoryProtocol

    init(repository: LiveDuelInviteRepositoryProtocol,
         matchRepo: MatchRepositoryProtocol,
         questionRepo: QuestionRepositoryProtocol) {
        self.repository = repository
        self.matchRepo = matchRepo
        self.questionRepo = questionRepo
    }

    func createRoom(topicID: String) async throws -> LiveDuelInvite {
        try await repository.createInvite(topicID: topicID)
    }

    func joinRoom(code: String) async throws -> JoinedLiveDuelInvite {
        try await repository.joinInvite(code: code)
    }

    func resolveTopic(fromUUID uuid: String) async throws -> Topic? {
        let slug = try await repository.resolveTopicSlug(fromUUID: uuid)
        return QuestionBank.topic(slug)
    }

    func questionIDs(for matchID: String) async throws -> [String] {
        try await matchRepo.questionIDs(for: matchID)
    }

    func fetchQuestions(questionIDs: [String]) async throws -> [Question] {
        try await questionRepo.fetchQuestions(questionIDs: questionIDs)
    }
}
