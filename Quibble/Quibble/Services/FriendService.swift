import Foundation

final class FriendService {
    private let repository: FriendRepositoryProtocol

    init(repository: FriendRepositoryProtocol) {
        self.repository = repository
    }

    func ensureFriendCode() async throws -> String {
        try await repository.ensureFriendCode()
    }

    func lookupFriend(code: String) async throws -> PublicFriendProfile {
        try await repository.lookupProfile(friendCode: code)
    }

    func sendRequest(code: String) async throws -> Friendship {
        try await repository.sendFriendRequest(friendCode: code)
    }

    func incomingRequests() async throws -> [Friendship] {
        try await repository.incomingRequests()
    }

    func outgoingRequests() async throws -> [Friendship] {
        try await repository.outgoingRequests()
    }

    func acceptedFriends() async throws -> [Friendship] {
        try await repository.acceptedFriendships()
    }

    func acceptRequest(_ friendshipID: String) async throws -> Friendship {
        try await repository.acceptRequest(friendshipID)
    }

    func declineRequest(_ friendshipID: String) async throws -> Friendship {
        try await repository.declineRequest(friendshipID)
    }

    func cancelRequest(_ friendshipID: String) async throws -> Friendship {
        try await repository.cancelRequest(friendshipID)
    }
}
