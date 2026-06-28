import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var app: AppState
    var isTab: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Activity", showBack: !isTab)
                    .padding(.top, 8)

                // Incoming friend requests
                if !app.incomingFriendRequests.isEmpty {
                    SectionHeader(title: "Incoming friend requests")
                    VStack(spacing: 10) {
                        ForEach(app.incomingFriendRequests) { req in
                            IncomingRequestCard(request: req)
                        }
                    }
                }

                // Outgoing friend requests
                if !app.outgoingFriendRequests.isEmpty {
                    SectionHeader(title: "Outgoing friend requests")
                    VStack(spacing: 10) {
                        ForEach(app.outgoingFriendRequests) { req in
                            OutgoingRequestCard(request: req)
                        }
                    }
                }

                // Active live room
                if let pending = app.pendingLiveRoom {
                    SectionHeader(title: "Live room ready")
                    LiveRoomActivityCard(invite: pending.invite, topicName: pending.topic.name)
                }

                // Waiting matches
                if !app.waitingMatches.isEmpty {
                    SectionHeader(title: "Waiting for opponent")
                    VStack(spacing: 10) {
                        ForEach(app.waitingMatches) { result in
                            WaitingMatchCard(result: result)
                        }
                    }
                }

                // Match history
                SectionHeader(title: "Match history")
                if app.history.isEmpty {
                    EmptyStateView(mascot: .sleepy, color: .softBlue,
                                   title: "No battles yet",
                                   message: "Your duels will pile up here.\nGo start one — it only takes a minute.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(app.history) { record in
                            NavigationLink {
                                ReviewAnswersView(answers: record.answers,
                                                  opponentName: record.opponentName)
                            } label: {
                                MatchRow(record: record)
                            }
                            .buttonStyle(NeoPressStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 110)
        }
        .background(Color.cream.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await app.loadFriends()
        }
    }
}

// MARK: - Waiting match card

private struct WaitingMatchCard: View {
    let result: MatchResult

    var body: some View {
        HStack(spacing: 12) {
            MascotView(state: .thinking, color: .quibPurple, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Async duel saved")
                    .font(.quib(14, .heavy))
                    .foregroundStyle(Color.ink)
                Text("Your \(result.player.score) points are waiting for another player.")
                    .font(.quib(11, .bold))
                    .foregroundStyle(Color.mutedText)
            }
            Spacer()
            ChipView(text: "Waiting", icon: "hourglass", fill: Palette.pastel("purple"))
        }
        .padding(13)
        .neoCard(.paper, radius: 18, shadow: 3)
    }
}

// MARK: - Incoming friend request card

private struct IncomingRequestCard: View {
    @EnvironmentObject private var app: AppState
    let request: Friendship

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(colorName: request.otherProfile?.avatarSeed ?? "yellow",
                       size: 40, state: .surprised)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.otherProfile?.displayName ?? "Player")
                    .font(.quib(14, .heavy))
                    .foregroundStyle(Color.ink)
                Text("Wants to be friends")
                    .font(.quib(11, .bold))
                    .foregroundStyle(Color.mutedText)
            }
            Spacer()
            Button {
                Haptics.tap()
                Task { await app.acceptFriendRequest(request.id) }
            } label: {
                Text("Accept")
            }
            .buttonStyle(NeoButtonStyle(fill: .quibGreen, textColor: .paper))
            Button {
                Haptics.tap()
                Task { await app.declineFriendRequest(request.id) }
            } label: {
                Text("Decline")
            }
            .buttonStyle(NeoButtonStyle(fill: .paper))
        }
        .padding(13)
        .neoCard(Palette.pastel("yellow"), radius: 18, shadow: 3)
    }
}

// MARK: - Outgoing friend request card

private struct OutgoingRequestCard: View {
    @EnvironmentObject private var app: AppState
    let request: Friendship

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(colorName: request.otherProfile?.avatarSeed ?? "yellow",
                       size: 40, state: .thinking)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.otherProfile?.displayName ?? "Player")
                    .font(.quib(14, .heavy))
                    .foregroundStyle(Color.ink)
                Text("Request sent — waiting")
                    .font(.quib(11, .bold))
                    .foregroundStyle(Color.mutedText)
            }
            Spacer()
            Button {
                Haptics.tap()
                Task { await app.cancelFriendRequest(request.id) }
            } label: {
                Text("Cancel")
            }
            .buttonStyle(NeoButtonStyle(fill: .paper))
        }
        .padding(13)
        .neoCard(Palette.pastel("blue"), radius: 18, shadow: 3)
    }
}

// MARK: - Live room activity card

private struct LiveRoomActivityCard: View {
    @EnvironmentObject private var app: AppState
    let invite: LiveDuelInvite
    let topicName: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MascotView(state: .excited, color: .quibRed, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live room: \(topicName)")
                        .font(.quib(14, .heavy))
                        .foregroundStyle(Color.ink)
                    Text("Code: \(invite.joinCode)")
                        .font(.quib(12, .bold))
                        .foregroundStyle(Color.mutedText)
                        .tracking(3)
                        .monospaced()
                }
                Spacer()
                ChipView(text: "Live", icon: "bolt.fill", fill: Palette.pastel("red"))
            }
            Button {
                Haptics.heavy()
                app.startHostLiveRoom()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start as host")
                }
            }
            .buttonStyle(NeoButtonStyle(fill: .quibGreen, textColor: .paper, fullWidth: true))
        }
        .padding(13)
        .neoCard(Palette.pastel("red"), radius: 20, shadow: 3)
    }
}
