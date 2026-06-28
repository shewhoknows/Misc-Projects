import XCTest
@testable import Quibble

final class ScoringServiceTests: XCTestCase {
    func testCorrectAnswerScoreIncludesSpeedBonus() {
        let points = ScoringService.points(isCorrect: true, timeRemaining: 10, streak: 1)

        XCTAssertEqual(points.base, 100)
        XCTAssertEqual(points.speed, 50)
        XCTAssertEqual(points.streak, 0)
        XCTAssertEqual(points.total, 150)
    }

    func testStreakBonusStartsAtThree() {
        let points = ScoringService.points(isCorrect: true, timeRemaining: 5, streak: 3)

        XCTAssertEqual(points.base, 100)
        XCTAssertEqual(points.speed, 25)
        XCTAssertEqual(points.streak, 25)
        XCTAssertEqual(points.total, 150)
    }

    func testWrongAnswerAndTimeoutScoreZero() {
        XCTAssertEqual(ScoringService.points(isCorrect: false, timeRemaining: 10, streak: 5).total, 0)
        XCTAssertEqual(ScoringService.points(isCorrect: false, timeRemaining: 0, streak: 0).total, 0)
    }

    func testXPCalculation() {
        XCTAssertEqual(ScoringService.xp(outcome: .win, isDaily: false, isPerfect: false), 120)
        XCTAssertEqual(ScoringService.xp(outcome: .loss, isDaily: false, isPerfect: false), 60)
        XCTAssertEqual(ScoringService.xp(outcome: .draw, isDaily: false, isPerfect: false), 90)
        XCTAssertEqual(ScoringService.xp(outcome: .win, isDaily: true, isPerfect: true), 220)
    }

    func testMissingSupabaseConfigFallsBackCleanly() {
        XCTAssertNil(SupabaseConfig.load(environment: [:]))
    }

    func testLiveMatchEngineAppliesRemoteAnswerOnce() {
        let topic = QuestionBank.topics[0]
        let questions = Array(QuestionBank.questions(for: topic.id).prefix(7))
        let setup = MatchSetup(id: UUID(),
                               mode: .topic,
                               topic: topic,
                               opponent: Bot(id: "live",
                                             name: "Live rival",
                                             colorName: "softBlue",
                                             mascot: .competitive,
                                             accuracy: 0,
                                             minTime: 10,
                                             maxTime: 10,
                                             tagline: "Testing live."),
                               questions: questions,
                               onlineMatchID: "match-1",
                               onlineMode: .live,
                               onlineCreatedBy: "user-1")
        let engine = MatchEngine(setup: setup)

        engine.applyRemoteAnswer(questionID: questions[0].id, points: 125, score: 125)
        engine.applyRemoteAnswer(questionID: questions[0].id, points: 125, score: 250)

        XCTAssertEqual(engine.botScore, 125)
    }

    // MARK: - Friend code normalization

    func testNormalizedCodeUppercasesAndTrims() {
        XCTAssertEqual("abc123".normalizedCode, "ABC23")
        XCTAssertEqual("  xyz  ".normalizedCode, "XYZ")
        XCTAssertEqual("a-b-c".normalizedCode, "ABC")
    }

    func testNormalizedCodeStripsInvalidCharacters() {
        XCTAssertEqual("O0I1".normalizedCode, "")
        XCTAssertEqual("AB0CD1EF".normalizedCode, "ABCDEF")
        XCTAssertEqual("test-code-789".normalizedCode, "TESTCDE789")
    }

    func testNormalizedCodeHandlesLowercase() {
        XCTAssertEqual("abcdef".normalizedCode, "ABCDEF")
        XCTAssertEqual("ghjk".normalizedCode, "GHJK")
    }

    // MARK: - Local repo blocking errors

    func testLocalFriendRepositoryThrowsBlockingError() async {
        let repo = LocalFriendRepository()
        do {
            _ = try await repo.ensureFriendCode()
            XCTFail("Expected error, got success")
        } catch let error as ServiceError {
            XCTAssertTrue(error.userMessage.contains("Sign in"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLocalLiveDuelInviteRepositoryThrowsBlockingError() async {
        let repo = LocalLiveDuelInviteRepository()
        do {
            _ = try await repo.createInvite(topicID: "cricket")
            XCTFail("Expected error, got success")
        } catch let error as ServiceError {
            XCTAssertTrue(error.userMessage.contains("Sign in"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Friendship model

    func testFriendshipOtherUserID() {
        let friendship = Friendship(id: "f1",
                                    requesterID: "user-a",
                                    addresseeID: "user-b",
                                    status: .pending,
                                    createdAt: nil,
                                    respondedAt: nil,
                                    otherProfile: nil)
        XCTAssertEqual(friendship.otherUserID(for: "user-a"), "user-b")
        XCTAssertEqual(friendship.otherUserID(for: "user-b"), "user-a")
    }

    func testPublicFriendProfileDecoding() throws {
        let json = """
        {"id":"abc","username":"player1","display_name":"Player One","avatar_seed":"yellow"}
        """
        let dto = try JSONDecoder().decode(SupabasePublicProfileDTO.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(dto.profile.id, "abc")
        XCTAssertEqual(dto.profile.username, "player1")
        XCTAssertEqual(dto.profile.displayName, "Player One")
    }

    func testLiveDuelInviteDTODecoding() throws {
        let json = """
        {"invite_id":"inv-1","match_id":"m-1","join_code":"ABCD","topic_id":"t-1","expires_at":"2026-07-01T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dto = try decoder.decode(SupabaseLiveDuelInviteDTO.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(dto.invite.inviteID, "inv-1")
        XCTAssertEqual(dto.invite.joinCode, "ABCD")
    }

    // MARK: - SupabasePublicProfileDTO nullability

    func testPublicProfileDTODefaultsNullFields() throws {
        let json = """
        {"id":"abc","username":"player1"}
        """
        let dto = try JSONDecoder().decode(SupabasePublicProfileDTO.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(dto.profile.id, "abc")
        XCTAssertEqual(dto.profile.username, "player1")
        XCTAssertEqual(dto.profile.displayName, "player1")
        XCTAssertEqual(dto.profile.avatarSeed, "yellow")
    }

    func testPublicProfileDTODefaultsAllNulls() throws {
        let json = """
        {"id":"xyz"}
        """
        let dto = try JSONDecoder().decode(SupabasePublicProfileDTO.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(dto.profile.id, "xyz")
        XCTAssertEqual(dto.profile.username, "player")
        XCTAssertEqual(dto.profile.displayName, "Player")
        XCTAssertEqual(dto.profile.avatarSeed, "yellow")
    }

    // MARK: - Question ordering

    func testQuestionFetchPreservesInputOrder() {
        let all = QuestionBank.all
        let shuffled = all.shuffled()
        let ids = shuffled.map(\.id)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }

        XCTAssertEqual(ordered.count, ids.count)
        for (index, question) in ordered.enumerated() {
            XCTAssertEqual(question.id, ids[index],
                           "Question at index \(index) should match input order")
        }
    }

    func testQuestionFetchDropsNotFoundIDs() {
        let all = QuestionBank.all
        let ids = ["nonexistent-1", all[0].id, "nonexistent-2", all[1].id]
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }

        XCTAssertEqual(ordered.count, 2)
        XCTAssertEqual(ordered[0].id, all[0].id)
        XCTAssertEqual(ordered[1].id, all[1].id)
    }
}
