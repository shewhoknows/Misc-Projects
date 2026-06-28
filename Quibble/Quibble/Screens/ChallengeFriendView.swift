import SwiftUI

struct ChallengeFriendView: View {
    @EnvironmentObject private var app: AppState

    // Friend code lookup
    @State private var lookupCode = ""

    // Live room
    @State private var selectedLiveTopic: Topic?
    @State private var joinRoomCode = ""

    private let topicColumns = [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Challenge a Friend")
                    .padding(.top, 8)

                // MARK: - Your friend code
                friendCodeSection

                // MARK: - Lookup & add friend
                lookupSection

                // MARK: - Accepted friends
                friendsSection

                // MARK: - Incoming requests
                if !app.incomingFriendRequests.isEmpty {
                    SectionHeader(title: "Incoming requests")
                    incomingRequestsSection
                }

                // MARK: - Outgoing requests
                if !app.outgoingFriendRequests.isEmpty {
                    SectionHeader(title: "Outgoing requests")
                    outgoingRequestsSection
                }

                // MARK: - Live room
                SectionHeader(title: "Live duel room")
                liveRoomTopicPicker
                liveRoomActions
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 110)
        }
        .background(Color.cream.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await app.ensureFriendCode()
            await app.loadFriends()
        }
    }

    // MARK: - Friend code

    private var friendCodeSection: some View {
        VStack(spacing: 12) {
            if let code = app.friendCode {
                HStack(spacing: 10) {
                    Image(systemName: "person.line.dotted.person.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Color.quibPurple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your friend code")
                            .font(.quib(13, .heavy))
                            .foregroundStyle(Color.mutedText)
                        Text(code)
                            .font(.quib(22))
                            .foregroundStyle(Color.ink)
                            .tracking(4)
                            .monospaced()
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = code
                        Haptics.tap()
                        app.showToast("Code copied!")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 15, weight: .black))
                    }
                    .buttonStyle(NeoIconButtonStyle(fill: .paper, size: 40))
                    ShareLink(item: code) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .black))
                    }
                    .buttonStyle(NeoIconButtonStyle(fill: .paper, size: 40))
                }
                Text("Share this code with a friend to challenge them.")
                    .font(.quib(11, .bold))
                    .foregroundStyle(Color.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if app.profile.isSignedInWithApple {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading friend code…")
                        .font(.quib(13, .bold))
                        .foregroundStyle(Color.mutedText)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Color.mutedText)
                    Text("Sign in with Apple in Profile to get your friend code.")
                        .font(.quib(13, .bold))
                        .foregroundStyle(Color.mutedText)
                }
            }
        }
        .padding(16)
        .neoCard(.paper, radius: 20, shadow: 3)
    }

    // MARK: - Lookup

    private var lookupSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Enter friend code", text: $lookupCode)
                    .font(.quib(15))
                    .foregroundStyle(Color.ink)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14).fill(Color.paper)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.ink, lineWidth: 2.5)
                    )
                    .onChange(of: lookupCode) { _, newValue in
                        lookupCode = String(newValue.prefix(16))
                    }

                Button {
                    Haptics.tap()
                    let normalized = lookupCode.normalizedCode
                    guard !normalized.isEmpty else { return }
                    Task { await app.lookupFriendCode(normalized) }
                } label: {
                    Text("Look up")
                }
                .buttonStyle(NeoButtonStyle(fill: .quibBlue, textColor: .paper))
                .disabled(lookupCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(lookupCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }

            // Lookup result
            if let result = app.friendSearchResult {
                HStack(spacing: 12) {
                    AvatarView(colorName: result.avatarSeed, size: 44, state: .happy)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.displayName)
                            .font(.quib(15, .heavy))
                            .foregroundStyle(Color.ink)
                        Text("@\(result.username)")
                            .font(.quib(11, .bold))
                            .foregroundStyle(Color.mutedText)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        let code = lookupCode.normalizedCode
                        guard !code.isEmpty else { return }
                        Task {
                            await app.sendFriendRequest(to: code)
                            if app.serviceStatus == .ready {
                                app.friendSearchResult = nil
                                lookupCode = ""
                            }
                        }
                    } label: {
                        Text("Send request")
                    }
                    .buttonStyle(NeoButtonStyle(fill: .quibGreen, textColor: .paper))
                }
                .padding(13)
                .neoCard(Palette.pastel("green"), radius: 18, shadow: 3)
            }

            // Lookup error
            if case .failed(let message) = app.serviceStatus, app.friendSearchResult == nil {
                Text(message)
                    .font(.quib(11, .bold))
                    .foregroundStyle(Color.quibRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .neoCard(.paper, radius: 20, shadow: 3)
    }

    // MARK: - Friends list

    private var friendsSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "My friends")
            if app.friends.isEmpty {
                Text("No friends yet. Share your code above!")
                    .font(.quib(12, .bold))
                    .foregroundStyle(Color.mutedText)
                    .padding(.vertical, 10)
            } else {
                ForEach(app.friends) { friendship in
                    friendRow(friendship)
                }
            }
        }
    }

    @ViewBuilder
    private func friendRow(_ friendship: Friendship) -> some View {
        HStack(spacing: 12) {
            AvatarView(colorName: friendship.otherProfile?.avatarSeed ?? "yellow",
                       size: 40, state: .happy)
            VStack(alignment: .leading, spacing: 1) {
                Text(friendship.otherProfile?.displayName ?? "Friend")
                    .font(.quib(15, .heavy))
                    .foregroundStyle(Color.ink)
                if let username = friendship.otherProfile?.username {
                    Text("@\(username)")
                        .font(.quib(11, .bold))
                        .foregroundStyle(Color.mutedText)
                }
            }
            Spacer()
            ChipView(text: "Friend", icon: "person.fill.checkmark",
                     fill: Palette.pastel("green"))
        }
        .padding(12)
        .neoCard(.paper, radius: 18, shadow: 3, lineWidth: 2.5)
    }

    // MARK: - Incoming requests

    private var incomingRequestsSection: some View {
        VStack(spacing: 10) {
            ForEach(app.incomingFriendRequests) { req in
                HStack(spacing: 12) {
                    AvatarView(colorName: req.otherProfile?.avatarSeed ?? "yellow",
                               size: 40, state: .surprised)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(req.otherProfile?.displayName ?? "Player")
                            .font(.quib(15, .heavy))
                            .foregroundStyle(Color.ink)
                        Text("Wants to be friends")
                            .font(.quib(11, .bold))
                            .foregroundStyle(Color.mutedText)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        Task { await app.acceptFriendRequest(req.id) }
                    } label: {
                        Text("Accept")
                    }
                    .buttonStyle(NeoButtonStyle(fill: .quibGreen, textColor: .paper))
                    Button {
                        Haptics.tap()
                        Task { await app.declineFriendRequest(req.id) }
                    } label: {
                        Text("Decline")
                    }
                    .buttonStyle(NeoButtonStyle(fill: .paper))
                }
                .padding(13)
                .neoCard(Palette.pastel("yellow"), radius: 18, shadow: 3)
            }
        }
    }

    // MARK: - Outgoing requests

    private var outgoingRequestsSection: some View {
        VStack(spacing: 10) {
            ForEach(app.outgoingFriendRequests) { req in
                HStack(spacing: 12) {
                    AvatarView(colorName: req.otherProfile?.avatarSeed ?? "yellow",
                               size: 40, state: .thinking)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(req.otherProfile?.displayName ?? "Player")
                            .font(.quib(15, .heavy))
                            .foregroundStyle(Color.ink)
                        Text("Request sent — waiting")
                            .font(.quib(11, .bold))
                            .foregroundStyle(Color.mutedText)
                    }
                    Spacer()
                    Button {
                        Haptics.tap()
                        Task { await app.cancelFriendRequest(req.id) }
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(NeoButtonStyle(fill: .paper))
                }
                .padding(13)
                .neoCard(Palette.pastel("blue"), radius: 18, shadow: 3)
            }
        }
    }

    // MARK: - Live room topic picker

    private var liveRoomTopicPicker: some View {
        LazyVGrid(columns: topicColumns, spacing: 10) {
            ForEach(QuestionBank.topics) { topic in
                Button {
                    Haptics.tap()
                    selectedLiveTopic = topic
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: topic.symbol)
                            .font(.system(size: 13, weight: .black))
                        Text(topic.name)
                            .font(.quib(13, .heavy))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .neoCard(selectedLiveTopic?.id == topic.id
                             ? Palette.color(topic.colorName).opacity(0.55)
                             : .paper,
                             radius: 14,
                             shadow: selectedLiveTopic?.id == topic.id ? 1 : 3,
                             lineWidth: 2.5)
                }
                .buttonStyle(NeoPressStyle())
            }
        }
    }

    // MARK: - Live room actions

    private var liveRoomActions: some View {
        VStack(spacing: 10) {
            // Create room
            Button {
                guard let topic = selectedLiveTopic else { return }
                Haptics.tap()
                Task { await app.createLiveRoom(topic: topic) }
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Create live room")
                }
            }
            .buttonStyle(NeoButtonStyle(fill: .quibRed, textColor: .paper, fullWidth: true))
            .disabled(selectedLiveTopic == nil)
            .opacity(selectedLiveTopic == nil ? 0.5 : 1)

            // Pending live room — show code + start
            if let pending = app.pendingLiveRoom {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Room code")
                                .font(.quib(11, .bold))
                                .foregroundStyle(Color.mutedText)
                            Text(pending.invite.joinCode)
                                .font(.quib(20))
                                .foregroundStyle(Color.ink)
                                .tracking(4)
                                .monospaced()
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = pending.invite.joinCode
                            Haptics.tap()
                            app.showToast("Code copied!")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15, weight: .black))
                        }
                        .buttonStyle(NeoIconButtonStyle(fill: .paper, size: 40))
                        ShareLink(item: pending.invite.joinCode) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .black))
                        }
                        .buttonStyle(NeoIconButtonStyle(fill: .paper, size: 40))
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
                    .buttonStyle(NeoButtonStyle(fill: .quibGreen, textColor: .paper, big: true, fullWidth: true))
                }
                .padding(14)
                .neoCard(Palette.pastel("red"), radius: 20, shadow: 4)
            }

            // Divider
            HStack {
                Rectangle().fill(Color.ink.opacity(0.15)).frame(height: 2)
                Text("or")
                    .font(.quib(12, .heavy))
                    .foregroundStyle(Color.mutedText)
                Rectangle().fill(Color.ink.opacity(0.15)).frame(height: 2)
            }
            .padding(.vertical, 4)

            // Join room
            HStack(spacing: 8) {
                TextField("Room code", text: $joinRoomCode)
                    .font(.quib(15))
                    .foregroundStyle(Color.ink)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14).fill(Color.paper)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.ink, lineWidth: 2.5)
                    )
                    .onChange(of: joinRoomCode) { _, newValue in
                        joinRoomCode = String(newValue.prefix(8))
                    }

                Button {
                    Haptics.tap()
                    let normalized = joinRoomCode.normalizedCode
                    guard !normalized.isEmpty else { return }
                    Task { await app.joinLiveRoom(code: normalized) }
                } label: {
                    Text("Join")
                }
                .buttonStyle(NeoButtonStyle(fill: .quibBlue, textColor: .paper))
                .disabled(joinRoomCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(joinRoomCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
        .padding(.top, 8)
    }
}
