import AuthenticationServices
import SwiftUI

// MARK: - Match summary handed to the results screen

struct XPLine: Identifiable, Equatable {
    let label: String
    let amount: Int
    var id: String { label }
}

struct MatchSummary: Equatable {
    let record: MatchRecord
    let xpLines: [XPLine]
    let totalXP: Int
    let unlocked: [Achievement]
}

// MARK: - App state

@MainActor
final class AppState: ObservableObject {

    @Published var profile: PlayerProfile {
        didSet { persist() }
    }
    @Published var history: [MatchRecord] {
        didSet { persist() }
    }
    @Published var pendingChallenges: [PendingChallenge] {
        didSet { persist() }
    }
    /// Per-topic IDs of questions already served ("shuffle bag") — no question
    /// repeats until a topic's whole pool has been played through.
    @Published var usedQuestions: [String: [String]] {
        didSet { persist() }
    }

    /// Non-nil while a duel flow (matchmaking → quiz → results) is presented.
    @Published var activeMatch: MatchSetup?
    @Published var selectedTab: MainTab = .home
    @Published var authSession: AuthSession?
    @Published var onlineMode: OnlineMode
    @Published var serviceStatus: ServiceStatus = .idle
    @Published var waitingMatches: [MatchResult] = []
    @Published var toast: String?

    /// Friend-code + live room state (Phase 2).
    @Published var friendCode: String?
    @Published var friendSearchResult: PublicFriendProfile?
    @Published var friends: [Friendship] = []
    @Published var incomingFriendRequests: [Friendship] = []
    @Published var outgoingFriendRequests: [Friendship] = []
    @Published var liveRoomInvite: LiveDuelInvite?
    @Published var pendingLiveRoom: PendingLiveRoom?

    private static let profileKey = "quibble.profile.v1"
    private static let historyKey = "quibble.history.v1"
    private static let challengesKey = "quibble.challenges.v1"
    private static let usedQuestionsKey = "quibble.usedQuestions.v1"
    private let services: AppServices
    private var toastWork: DispatchWorkItem?

    init(services: AppServices = AppServices()) {
        self.services = services
        onlineMode = services.config.onlineMode
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.profileKey),
           let saved = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            profile = saved
        } else {
            profile = PlayerProfile()
        }
        if let data = defaults.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([MatchRecord].self, from: data) {
            history = saved
        } else {
            history = []
        }
        if let data = defaults.data(forKey: Self.challengesKey),
           let saved = try? JSONDecoder().decode([PendingChallenge].self, from: data) {
            pendingChallenges = saved
        } else {
            pendingChallenges = []
        }
        if let data = defaults.data(forKey: Self.usedQuestionsKey),
           let saved = try? JSONDecoder().decode([String: [String]].self, from: data) {
            usedQuestions = saved
        } else {
            usedQuestions = [:]
        }
        Haptics.enabled = profile.hapticsOn
        Task { await establishGuestSession() }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.profileKey)
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
        if let data = try? JSONEncoder().encode(pendingChallenges) {
            defaults.set(data, forKey: Self.challengesKey)
        }
        if let data = try? JSONEncoder().encode(usedQuestions) {
            defaults.set(data, forKey: Self.usedQuestionsKey)
        }
        Haptics.enabled = profile.hapticsOn
    }

    func resetAllData() {
        profile = PlayerProfile()
        history = []
        pendingChallenges = []
        usedQuestions = [:]
        waitingMatches = []
        friendCode = nil
        friendSearchResult = nil
        friends = []
        incomingFriendRequests = []
        outgoingFriendRequests = []
        liveRoomInvite = nil
        Task { await establishGuestSession() }
    }

    // MARK: - Question drawing (no repeats until a topic's pool is exhausted)

    func drawQuestions(topicID: String, count: Int = 7) -> [Question] {
        let pool = QuestionBank.questions(for: topicID)
        guard pool.count > count else { return pool.shuffled() }

        let used = Set(usedQuestions[topicID] ?? [])
        var picks = Array(pool.filter { !used.contains($0.id) }.shuffled().prefix(count))

        if picks.count < count {
            // Cycle complete — start a fresh bag, avoiding repeats within this match.
            let alreadyPicked = Set(picks.map(\.id))
            let refill = pool.filter { !alreadyPicked.contains($0.id) }.shuffled()
            picks += refill.prefix(count - picks.count)
            usedQuestions[topicID] = picks.map(\.id)
        } else {
            usedQuestions[topicID] = Array(used) + picks.map(\.id)
        }
        return picks.shuffled()
    }

    func drawMixedSet(count: Int = 7) -> [Question] {
        QuestionBank.topics.shuffled().prefix(count).compactMap { topic in
            drawQuestions(topicID: topic.id, count: 1).first
        }
    }

    // MARK: - Apple sign-in

    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async -> Bool {
        profile.appleUserID = credential.user
        profile.appleEmail = credential.email

        let parts = [
            credential.fullName?.givenName,
            credential.fullName?.familyName
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            profile.name = String(parts.joined(separator: " ").prefix(14))
        }

        serviceStatus = .loading
        do {
            authSession = try await services.auth.appleSession(credential: credential,
                                                               rawNonce: rawNonce,
                                                               fallback: profile)
            onlineMode = .remote
            serviceStatus = .ready
            showToast("Signed in with Apple")
            return true
        } catch let error as ServiceError {
            let fallback = UserProfile(id: credential.user,
                                       username: profile.name.lowercased().replacingOccurrences(of: " ", with: "_"),
                                       displayName: profile.name,
                                       avatarSeed: profile.colorName,
                                       totalXP: profile.xp,
                                       currentStreak: profile.dailyStreak,
                                       createdAt: nil,
                                       updatedAt: nil)
            authSession = .apple(fallback)
            onlineMode = .offlineFallback
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
            return false
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
            return false
        }
    }

    func signOutOfApple() {
        services.auth.signOut()
        profile.appleUserID = nil
        profile.appleEmail = nil
        authSession = nil
        showToast("Signed out")
        Task { await establishGuestSession() }
    }

    func establishGuestSession() async {
        if let restored = await services.auth.restoreRemoteSession(localProfile: profile) {
            authSession = restored
            onlineMode = .remote
        } else {
            authSession = await services.auth.guestSession(from: profile)
            onlineMode = services.config.onlineMode
        }
    }

    func signInWithEmail(email: String, password: String) async -> Bool {
        serviceStatus = .loading
        do {
            authSession = try await services.auth.signIn(email: email, password: password, fallback: profile)
            onlineMode = .remote
            serviceStatus = .ready
            showToast("Signed in")
            return true
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
            return false
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
            return false
        }
    }

    func createAccount(email: String, password: String, username: String) async -> Bool {
        serviceStatus = .loading
        do {
            authSession = try await services.auth.signUp(email: email,
                                                         password: password,
                                                         username: username,
                                                         displayName: profile.name,
                                                         avatarSeed: profile.colorName)
            onlineMode = .remote
            serviceStatus = .ready
            showToast("Account created")
            return true
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
            return false
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
            return false
        }
    }

    func signOutRemoteAccount() {
        services.auth.signOut()
        profile.appleUserID = nil
        profile.appleEmail = nil
        authSession = nil
        showToast("Signed out")
        Task { await establishGuestSession() }
    }

    // MARK: - Toasts

    func showToast(_ message: String) {
        toastWork?.cancel()
        withAnimation(.spring(duration: 0.3)) { toast = message }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    // MARK: - Starting matches

    func startQuickDuel() {
        let pool = profile.favoriteTopicIDs.compactMap { QuestionBank.topic($0) }
        let topic = pool.randomElement() ?? QuestionBank.topics.randomElement()!
        start(setup: MatchSetup(id: UUID(), mode: .quick, topic: topic,
                                opponent: MockData.randomBot(),
                                questions: drawQuestions(topicID: topic.id)))
    }

    func startTopicDuel(_ topic: Topic) {
        serviceStatus = .loading
        Task {
            let userID = authSession?.profile.id ?? "guest"
            let draft = await services.matches.prepareAsyncDuel(topic: topic, userID: userID)
            onlineMode = draft.mode
            serviceStatus = .ready
            if draft.mode != .remote {
                showToast("No online duel yet. Playing a bot.")
            } else if draft.match?.status == .waiting {
                showToast("Async duel created. Your result will wait for an opponent.")
            }
            start(setup: MatchSetup(id: UUID(),
                                    mode: .topic,
                                    topic: topic,
                                    opponent: draft.opponent ?? MockData.randomBot(),
                                    questions: draft.questions,
                                    onlineMatchID: draft.match?.id,
                                    onlineMode: draft.mode,
                                    onlineCreatedBy: draft.match?.createdBy))
        }
    }

    func startLiveDuel(_ topic: Topic) {
        serviceStatus = .loading
        Task {
            let userID = authSession?.profile.id ?? "guest"
            let draft = await services.matches.prepareLiveDuel(topic: topic, userID: userID)
            onlineMode = draft.mode
            serviceStatus = .ready
            if draft.mode == .live {
                if draft.match?.status == .waiting {
                    showToast("Live room created. Waiting for a challenger.")
                } else {
                    showToast("Live challenger found.")
                }
            } else {
                showToast("Live room unavailable. Playing a bot.")
            }
            start(setup: MatchSetup(id: UUID(),
                                    mode: .topic,
                                    topic: topic,
                                    opponent: draft.opponent ?? Bot(id: "live-rival",
                                                                    name: "Live rival",
                                                                    colorName: "softBlue",
                                                                    mascot: .competitive,
                                                                    accuracy: 0,
                                                                    minTime: 10,
                                                                    maxTime: 10,
                                                                    tagline: "Answering right now."),
                                    questions: draft.questions,
                                    onlineMatchID: draft.match?.id,
                                    onlineMode: draft.mode,
                                    onlineCreatedBy: draft.match?.createdBy))
        }
    }

    func startDailyChallenge() {
        serviceStatus = .loading
        Task {
            let userID = authSession?.profile.id
            let challenge = await services.dailyChallenge.today(userID: userID)
            serviceStatus = .ready
            start(setup: MatchSetup(id: UUID(),
                                    mode: .daily,
                                    topic: challenge.topicID.flatMap { QuestionBank.topic($0) },
                                    opponent: MockData.dailyBot,
                                    questions: challenge.questions,
                                    onlineMatchID: challenge.id,
                                    onlineMode: onlineMode))
        }
    }

    func startFriendDuel(_ friend: Friend, topic: Topic) {
        start(setup: MatchSetup(id: UUID(), mode: .friend, topic: topic,
                                opponent: MockData.bot(for: friend),
                                questions: drawQuestions(topicID: topic.id)))
    }

    private func start(setup: MatchSetup) {
        Haptics.heavy()
        activeMatch = setup
    }

    /// Fresh questions, same opponent — the "one more round" button.
    func rematchSetup(from setup: MatchSetup) -> MatchSetup {
        let questions: [Question]
        if let topic = setup.topic {
            questions = drawQuestions(topicID: topic.id)
        } else {
            // Mixed rematch: one unseen question each from 7 random topics.
            questions = drawMixedSet()
        }
        return MatchSetup(id: UUID(), mode: setup.mode, topic: setup.topic,
                          opponent: setup.opponent, questions: questions,
                          onlineMatchID: setup.onlineMatchID,
                          onlineMode: setup.onlineMode,
                          onlineCreatedBy: setup.onlineCreatedBy)
    }

    func connectLiveSession(_ session: LiveDuelSession, setup: MatchSetup) {
        guard setup.isLive, let matchID = setup.onlineMatchID else { return }
        let userID = authSession?.profile.id ?? "guest"
        session.connect(client: services.liveDuels.makeClient(matchID: matchID),
                        userID: userID,
                        displayName: profile.name,
                        colorName: profile.colorName)
    }

    // MARK: - Recording a finished match

    func recordMatch(setup: MatchSetup, answers: [AnswerRecord],
                     yourScore: Int, botScore: Int) -> MatchSummary {
        let outcome: MatchOutcome =
            yourScore > botScore ? .win : (yourScore < botScore ? .loss : .draw)

        var lines: [XPLine] = []
        switch outcome {
        case .win:  lines.append(XPLine(label: "Victory", amount: 120))
        case .loss: lines.append(XPLine(label: "Good fight", amount: 60))
        case .draw: lines.append(XPLine(label: "Dead heat", amount: 90))
        }

        let correctCount = answers.filter(\.isCorrect).count
        if correctCount == answers.count && !answers.isEmpty {
            lines.append(XPLine(label: "Perfect 7", amount: 50))
        }

        let today = DateKeys.today
        if setup.mode == .daily && profile.lastDailyDate != today {
            lines.append(XPLine(label: "Daily challenge", amount: 50))
            if profile.lastDailyDate == DateKeys.yesterday {
                profile.dailyStreak += 1
            } else {
                profile.dailyStreak = 1
            }
            profile.bestDailyStreak = max(profile.bestDailyStreak, profile.dailyStreak)
            profile.lastDailyDate = today
        }

        let totalXP = lines.map(\.amount).reduce(0, +)

        let weekKey = DateKeys.weekKey
        if profile.weekKey != weekKey {
            profile.weekKey = weekKey
            profile.weeklyXP = 0
        }
        profile.xp += totalXP
        profile.weeklyXP += totalXP

        let record = MatchRecord(
            id: UUID(), date: Date(), mode: setup.mode,
            topicID: setup.topicID, topicName: setup.topicName,
            opponentName: setup.opponent.name,
            opponentColorName: setup.opponent.colorName,
            yourScore: yourScore, opponentScore: botScore,
            outcome: outcome, xpEarned: totalXP, answers: answers)
        history.insert(record, at: 0)

        if let matchID = setup.onlineMatchID {
            let userID = authSession?.profile.id ?? "guest"
            Task {
                if let result = await services.matches.submitResult(matchID: matchID,
                                                                     userID: userID,
                                                                     answers: answers,
                                                                     topicID: setup.topicID),
                   result.isWaitingForOpponent {
                    waitingMatches.insert(result, at: 0)
                    showToast("Result saved. Waiting for opponent.")
                }
            }
        }

        if setup.mode == .daily {
            let userID = authSession?.profile.id ?? "guest"
            let result = DailyChallengeResult(id: UUID().uuidString,
                                              challengeID: setup.onlineMatchID ?? DateKeys.today,
                                              userID: userID,
                                              score: yourScore,
                                              correctCount: correctCount,
                                              xpGained: totalXP,
                                              completedAt: Date())
            Task { _ = await services.dailyChallenge.submit(result: result) }
        }

        let unlocked = evaluateAchievements()
        return MatchSummary(record: record, xpLines: lines, totalXP: totalXP, unlocked: unlocked)
    }

    // MARK: - Derived stats

    var totalMatches: Int { history.count }
    var totalWins: Int { history.filter { $0.outcome == .win }.count }
    var winRate: Int {
        totalMatches == 0 ? 0 : Int((Double(totalWins) / Double(totalMatches) * 100).rounded())
    }
    var bestScore: Int { history.map(\.yourScore).max() ?? 0 }
    var distinctTopicsPlayed: Int { Set(history.map(\.topicID)).count }
    var dailyDoneToday: Bool { profile.lastDailyDate == DateKeys.today }

    func topicStats(_ topicID: String) -> (played: Int, wins: Int, best: Int) {
        let games = history.filter { $0.topicID == topicID }
        return (games.count,
                games.filter { $0.outcome == .win }.count,
                games.map(\.yourScore).max() ?? 0)
    }

    /// Days (as "yyyy-MM-dd") on which a daily challenge was completed.
    var dailyCompletionDays: Set<String> {
        Set(history.filter { $0.mode == .daily }.map { DateKeys.key(for: $0.date) })
    }

    // MARK: - Leaderboards

    func leaderboard(weekly: Bool) -> [LeaderboardEntry] {
        let weekKey = DateKeys.weekKey
        var entries = MockData.leaderboardSeeds.map { seed in
            LeaderboardEntry(id: seed.name, name: seed.name, colorName: seed.colorName,
                             xp: weekly ? MockData.weeklyXP(for: seed, weekKey: weekKey) : seed.baseXP,
                             isPlayer: false)
        }
        entries.append(LeaderboardEntry(id: "player", name: profile.name,
                                        colorName: profile.colorName,
                                        xp: weekly ? profile.weeklyXP : profile.xp,
                                        isPlayer: true))
        return entries.sorted { $0.xp > $1.xp }
    }

    func friendLeaderboard() -> [LeaderboardEntry] {
        let acceptedFriends = friends.filter { $0.status == .accepted && $0.otherProfile != nil }
        var entries = acceptedFriends.map { friendship in
            let p = friendship.otherProfile!
            let name = p.displayName.isEmpty ? p.username : p.displayName
            return LeaderboardEntry(id: p.id, name: name, colorName: p.avatarSeed,
                                    xp: 0, isPlayer: false)
        }
        entries.append(LeaderboardEntry(id: "player", name: profile.name,
                                        colorName: profile.colorName,
                                        xp: profile.xp, isPlayer: true))
        return entries.sorted { $0.xp > $1.xp }
    }

    func loadTopicLeaderboard(topicID: String, limit: Int = 20) async -> [LeaderboardEntry] {
        await services.leaderboards.topicLeaderboard(topicID: topicID, limit: limit)
    }

    func loadDailyLeaderboard(limit: Int = 20) async -> [LeaderboardEntry] {
        await services.leaderboards.dailyLeaderboard(dateKey: DateKeys.today, limit: limit)
    }

    // MARK: - Friend challenges (mock)

    func sendChallenge(to friend: Friend, topic: Topic) {
        pendingChallenges.insert(
            PendingChallenge(id: UUID(), friendName: friend.name,
                             friendColorName: friend.colorName,
                             topicID: topic.id, topicName: topic.name, date: Date()),
            at: 0)
        profile.challengesSent += 1
        let unlocked = evaluateAchievements()
        showToast("Challenge sent to \(friend.name)! (demo)")
        if let first = unlocked.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
                self?.showToast("Achievement unlocked: \(first.name)!")
            }
        }
    }

    func removeChallenge(_ challenge: PendingChallenge) {
        pendingChallenges.removeAll { $0.id == challenge.id }
    }

    // MARK: - Friend codes & live rooms

    private var needsRemoteSession: Bool {
        guard let session = authSession, !session.isGuest else {
            showToast("Sign in with Apple to use friend codes.")
            return false
        }
        return true
    }

    func ensureFriendCode() async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            friendCode = try await services.friends.ensureFriendCode()
            serviceStatus = .ready
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func lookupFriendCode(_ code: String) async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            friendSearchResult = try await services.friends.lookupFriend(code: code)
            serviceStatus = .ready
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func sendFriendRequest(to code: String) async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            _ = try await services.friends.sendRequest(code: code)
            serviceStatus = .ready
            showToast("Friend request sent.")
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func loadFriends() async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            async let accepted = services.friends.acceptedFriends()
            async let incoming = services.friends.incomingRequests()
            async let outgoing = services.friends.outgoingRequests()
            friends = try await accepted
            incomingFriendRequests = try await incoming
            outgoingFriendRequests = try await outgoing
            serviceStatus = .ready
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func acceptFriendRequest(_ friendshipID: String) async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            _ = try await services.friends.acceptRequest(friendshipID)
            serviceStatus = .ready
            showToast("Friend request accepted.")
            await loadFriends()
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func declineFriendRequest(_ friendshipID: String) async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            _ = try await services.friends.declineRequest(friendshipID)
            serviceStatus = .ready
            showToast("Friend request declined.")
            await loadFriends()
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func cancelFriendRequest(_ friendshipID: String) async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            _ = try await services.friends.cancelRequest(friendshipID)
            serviceStatus = .ready
            showToast("Friend request cancelled.")
            await loadFriends()
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func createLiveRoom(topic: Topic) async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            let invite = try await services.liveInvites.createRoom(topicID: topic.id)
            liveRoomInvite = invite
            let questionIDs = try await services.liveInvites.questionIDs(for: invite.matchID)
            let questions = try await services.liveInvites.fetchQuestions(questionIDs: questionIDs)
            guard questions.count == 7 else { throw ServiceError.invalidResponse }
            serviceStatus = .ready
            showToast("Live room created. Share the code: \(invite.joinCode)")
            pendingLiveRoom = PendingLiveRoom(invite: invite, questions: questions, topic: topic)
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    func startHostLiveRoom() {
        guard let pending = pendingLiveRoom else { return }
        pendingLiveRoom = nil
        let opponent = Bot(id: "live-host",
                           name: "Live challenger",
                           colorName: "softBlue",
                           mascot: .competitive,
                           accuracy: 0, minTime: 10, maxTime: 10,
                           tagline: "Waiting in the room.")
        start(setup: MatchSetup(id: UUID(),
                                mode: .friend,
                                topic: pending.topic,
                                opponent: opponent,
                                questions: pending.questions,
                                onlineMatchID: pending.invite.matchID,
                                onlineMode: .live))
    }

    func joinLiveRoom(code: String) async {
        guard needsRemoteSession else { return }
        serviceStatus = .loading
        do {
            let joined = try await services.liveInvites.joinRoom(code: code)
            let questionIDs = try await services.liveInvites.questionIDs(for: joined.matchID)
            let questions = try await services.liveInvites.fetchQuestions(questionIDs: questionIDs)
            guard questions.count == 7 else { throw ServiceError.invalidResponse }
            let topic = try await services.liveInvites.resolveTopic(fromUUID: joined.topicID)
            serviceStatus = .ready
            showToast("Joined live room.")
            let opponent = Bot(id: "live-guest",
                               name: "Live opponent",
                               colorName: "softBlue",
                               mascot: .competitive,
                               accuracy: 0, minTime: 10, maxTime: 10,
                               tagline: "Facing off now.")
            start(setup: MatchSetup(id: UUID(),
                                    mode: .friend,
                                    topic: topic,
                                    opponent: opponent,
                                    questions: questions,
                                    onlineMatchID: joined.matchID,
                                    onlineMode: .live))
        } catch let error as ServiceError {
            serviceStatus = .failed(error.userMessage)
            showToast(error.userMessage)
        } catch {
            serviceStatus = .failed(ServiceError.offline.userMessage)
            showToast(ServiceError.offline.userMessage)
        }
    }

    // MARK: - Achievements

    func isUnlocked(_ id: String) -> Bool {
        profile.unlockedAchievements.contains(id)
    }

    @discardableResult
    func evaluateAchievements() -> [Achievement] {
        var newly: [Achievement] = []
        func unlock(_ id: String, when condition: Bool) {
            guard condition, !profile.unlockedAchievements.contains(id) else { return }
            profile.unlockedAchievements.append(id)
            if let achievement = MockData.achievement(id) {
                newly.append(achievement)
            }
        }

        unlock("first_win", when: totalWins >= 1)
        unlock("perfect7", when: history.contains { $0.isPerfect })
        unlock("wins5", when: totalWins >= 5)
        unlock("wins25", when: totalWins >= 25)
        unlock("matches10", when: totalMatches >= 10)
        unlock("speedy", when: history.contains {
            $0.outcome == .win && $0.averageAnswerTime > 0 && $0.averageAnswerTime < 4
        })
        unlock("bigbrain", when: bestScore >= 900)
        unlock("explorer", when: distinctTopicsPlayed >= 5)
        unlock("daily1", when: !profile.lastDailyDate.isEmpty)
        unlock("streak3", when: profile.bestDailyStreak >= 3)
        unlock("streak7", when: profile.bestDailyStreak >= 7)
        unlock("instigator", when: profile.challengesSent >= 1)
        return newly
    }
}
