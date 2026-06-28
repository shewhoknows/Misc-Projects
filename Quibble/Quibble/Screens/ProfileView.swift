import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var app: AppState
    @State private var editingName = false
    @State private var draftName = ""
    @State private var confirmReset = false
    @State private var authError: String?
    @State private var currentAppleNonce: String?

    private let achievementColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Profile", showBack: false)
                    .padding(.top, 8)

                // Identity
                VStack(spacing: 14) {
                    MascotView(state: .happy,
                               color: Palette.color(app.profile.colorName),
                               size: 110)
                        .mascotBob()

                    if editingName {
                        HStack(spacing: 8) {
                            TextField("Your name", text: $draftName)
                                .font(.quib(17))
                                .foregroundStyle(Color.ink)
                                .padding(.vertical, 11)
                                .padding(.horizontal, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14).fill(Color.paper)
                                )
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ink, lineWidth: 2.5))
                                .submitLabel(.done)
                                .onSubmit(saveName)
                            Button(action: saveName) {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(NeoIconButtonStyle(fill: .quibGreen))
                        }
                    } else {
                        Button {
                            draftName = app.profile.name
                            editingName = true
                        } label: {
                            HStack(spacing: 7) {
                                Text(app.profile.name)
                                    .font(.quib(24))
                                    .foregroundStyle(Color.ink)
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(Color.mutedText)
                            }
                        }
                    }

                    // Blob color
                    HStack(spacing: 9) {
                        ForEach(["yellow", "pink", "blue", "green", "orange", "purple", "softBlue"], id: \.self) { name in
                            Button {
                                Haptics.tap()
                                app.profile.colorName = name
                            } label: {
                                Circle()
                                    .fill(Palette.color(name))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.ink, lineWidth: 2.5))
                                    .overlay {
                                        if app.profile.colorName == name {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .black))
                                                .foregroundStyle(Color.ink)
                                        }
                                    }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .neoCard(.paper, radius: 26, shadow: 5)

                // Account
                SectionHeader(title: "Account")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: accountIcon)
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color.ink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(accountFill))
                            .overlay(Circle().stroke(Color.ink, lineWidth: 2.5))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(accountTitle)
                                .font(.quib(15, .heavy))
                                .foregroundStyle(Color.ink)
                            Text(accountDetail)
                                .font(.quib(11, .bold))
                                .foregroundStyle(Color.mutedText)
                                .lineLimit(1)
                        }
                        Spacer()
                    }

                    if let code = app.friendCode {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Friend code")
                                    .font(.quib(11, .bold))
                                    .foregroundStyle(Color.mutedText)
                                Text(code)
                                    .font(.quib(17))
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
                            .buttonStyle(NeoIconButtonStyle(fill: .paper, size: 36))
                            ShareLink(item: code) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .black))
                            }
                            .buttonStyle(NeoIconButtonStyle(fill: .paper, size: 36))
                        }
                        Text("Share this code with a friend to challenge them.")
                            .font(.quib(11, .bold))
                            .foregroundStyle(Color.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if app.profile.isSignedInWithApple || isRemoteAccount {
                        Button {
                            Haptics.tap()
                            if app.profile.isSignedInWithApple {
                                app.signOutOfApple()
                            } else {
                                app.signOutRemoteAccount()
                            }
                        } label: {
                            Text("Sign out")
                        }
                        .buttonStyle(NeoButtonStyle(fill: .paper, fullWidth: true))
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                            let nonce = AppleSignInNonce.make()
                            currentAppleNonce = nonce
                            request.nonce = AppleSignInNonce.sha256(nonce)
                        } onCompletion: { result in
                            handleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.ink, lineWidth: 3)
                        )

                        if let authError {
                            Text(authError)
                                .font(.quib(11, .bold))
                                .foregroundStyle(Color.quibRed)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(16)
                .neoCard(.paper, radius: 20, shadow: 3)

                // Level
                VStack(spacing: 8) {
                    HStack {
                        Text("Level \(app.profile.level)")
                            .font(.quib(17))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text("\(app.profile.xpIntoLevel)/\(PlayerProfile.xpPerLevel) XP")
                            .font(.quib(12, .heavy))
                            .foregroundStyle(Color.mutedText)
                    }
                    XPBar(progress: app.profile.levelProgress)
                    Text("Total \(app.profile.xp) XP · \(app.profile.weeklyXP) XP this week")
                        .font(.quib(11, .bold))
                        .foregroundStyle(Color.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .neoCard(Palette.pastel("purple"), radius: 22, shadow: 4)

                // Stats
                SectionHeader(title: "Stats")
                HStack(spacing: 10) {
                    StatBox(value: "\(app.totalMatches)", label: "Duels")
                    StatBox(value: "\(app.totalWins)", label: "Wins")
                    StatBox(value: "\(app.winRate)%", label: "Win rate")
                }
                HStack(spacing: 10) {
                    StatBox(value: "\(app.bestScore)", label: "Best score")
                    StatBox(value: "\(app.profile.dailyStreak)", label: "Streak")
                    StatBox(value: "\(app.profile.bestDailyStreak)", label: "Best streak")
                }

                // Achievements preview
                SectionHeader(title: "Achievements")
                LazyVGrid(columns: achievementColumns, spacing: 12) {
                    ForEach(MockData.achievements.prefix(4)) { achievement in
                        AchievementCard(achievement: achievement,
                                        unlocked: app.isUnlocked(achievement.id))
                    }
                }
                NavigationLink {
                    StreakAchievementsView()
                } label: {
                    Text("See all achievements")
                }
                .buttonStyle(NeoButtonStyle(fill: .paper, fullWidth: true))

                // Settings
                SectionHeader(title: "Settings")
                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { app.profile.hapticsOn },
                        set: { app.profile.hapticsOn = $0 })) {
                        HStack(spacing: 10) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.system(size: 16, weight: .black))
                            Text("Haptics")
                                .font(.quib(15, .heavy))
                        }
                        .foregroundStyle(Color.ink)
                    }
                    .tint(.quibGreen)
                    .padding(16)
                }
                .neoCard(.paper, radius: 20, shadow: 3)

                Button {
                    confirmReset = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Reset all data")
                    }
                }
                .buttonStyle(NeoButtonStyle(fill: .quibRed, textColor: .paper, fullWidth: true))
                .confirmationDialog("Reset everything?",
                                    isPresented: $confirmReset,
                                    titleVisibility: .visible) {
                    Button("Wipe my XP, history and streak", role: .destructive) {
                        app.resetAllData()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears your local profile, matches and achievements.")
                }

                Text("Sign in with Apple to sync duels and challenge friends live.")
                    .font(.quib(11, .bold))
                    .foregroundStyle(Color.mutedText)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 110)
        }
        .background(Color.cream.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if app.profile.isSignedInWithApple {
                await app.ensureFriendCode()
            }
        }
    }

    private func saveName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            app.profile.name = String(trimmed.prefix(14))
        }
        editingName = false
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authError = "Apple sign-in did not return a profile."
                Haptics.error()
                return
            }
            authError = nil
            let nonce = currentAppleNonce
            currentAppleNonce = nil
            Task {
                let success = await app.signInWithApple(credential, rawNonce: nonce)
                await MainActor.run {
                    if success {
                        authError = nil
                        Haptics.success()
                    } else if case .failed(let message) = app.serviceStatus {
                        authError = message
                        Haptics.error()
                    } else {
                        authError = "Apple sign-in did not finish. Try again."
                        Haptics.error()
                    }
                }
            }
        case .failure(let error):
            currentAppleNonce = nil
            guard (error as? ASAuthorizationError)?.code != .canceled else { return }
            authError = "Apple sign-in failed. Try again."
            Haptics.error()
        }
    }

    private var accountDetail: String {
        if let session = app.authSession, !session.isGuest {
            return session.profile.username
        }
        if let email = app.profile.appleEmail, !email.isEmpty {
            return email
        }
        if app.profile.isSignedInWithApple {
            return "Apple account connected"
        }
        return "Sign in with Apple to sync duels and live matches."
    }

    private var isRemoteAccount: Bool {
        if case .remote = app.authSession { return true }
        return false
    }

    private var accountTitle: String {
        if isRemoteAccount { return "Signed in online" }
        if app.profile.isSignedInWithApple { return "Signed in with Apple" }
        return "Playing locally"
    }

    private var accountIcon: String {
        if app.profile.isSignedInWithApple { return "apple.logo" }
        if isRemoteAccount { return "checkmark.seal.fill" }
        return "person.crop.circle.badge.questionmark"
    }

    private var accountFill: Color {
        if app.profile.isSignedInWithApple { return Color.ink.opacity(0.08) }
        if isRemoteAccount { return Palette.pastel("green") }
        return .quibYellow
    }
}
