import Testing
import Foundation
@testable import KanbanCodeCore

@Suite("ChannelsStore — DMs")
struct DMStoreTests {
    private func tmpBase() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-dm-store-\(UUID().uuidString)").path
    }

    @Test func dmLogPathStableRegardlessOfOrder() async {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)
        let a = ChannelParticipant(cardId: "card_A", handle: "alice")
        let b = ChannelParticipant(cardId: "card_B", handle: "bob")
        let fwd = await store.dmLogPath(partyA: a, partyB: b)
        let rev = await store.dmLogPath(partyA: b, partyB: a)
        #expect(fwd == rev)
        #expect(fwd.contains("card_A__card_B") || fwd.contains("card_A") && fwd.contains("card_B"))
    }

    @Test func sendAndReadRoundTrip() async throws {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)
        let a = ChannelParticipant(cardId: "card_A", handle: "alice")
        let b = ChannelParticipant(cardId: "card_B", handle: "bob")
        let m1 = try await store.sendDirectMessage(from: a, to: b, body: "hey bob")
        let m2 = try await store.sendDirectMessage(from: b, to: a, body: "hi back")
        let msgs = await store.loadDMMessages(between: a, and: b)
        #expect(msgs.count == 2)
        #expect(msgs.map(\.body).sorted() == ["hey bob", "hi back"])
        // Newest at the end
        #expect(msgs.last?.id == m2.id || msgs.first?.id == m1.id)
    }

    @Test func channelMessageWithImagePathsPersistsAndReloads() async throws {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)
        // Create a temp source image for attachment.
        let srcPath = NSTemporaryDirectory() + "kanban-test-img-\(UUID().uuidString).png"
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: srcPath))
        defer { try? FileManager.default.removeItem(atPath: srcPath) }

        let a = ChannelParticipant(cardId: "card_A", handle: "alice")
        _ = try await store.createChannel(name: "pics", by: a)
        let msg = try await store.send(channel: "pics", from: a, body: "check this", imagePaths: [srcPath])

        #expect(msg.imagePaths?.count == 1)
        let persisted = msg.imagePaths?.first ?? ""
        #expect(FileManager.default.fileExists(atPath: persisted))
        #expect(persisted.contains("/images/\(msg.id)/"))

        // Reload from jsonl and verify paths survive the round-trip.
        let loaded = await store.loadMessages(channel: "pics")
        let roundtripped = loaded.first(where: { $0.id == msg.id })
        #expect(roundtripped?.imagePaths == msg.imagePaths)
    }

    @Test func dmMessageWithImagePathsPersistsAndReloads() async throws {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)
        let srcPath = NSTemporaryDirectory() + "kanban-test-img-\(UUID().uuidString).png"
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: srcPath))
        defer { try? FileManager.default.removeItem(atPath: srcPath) }

        let a = ChannelParticipant(cardId: "card_A", handle: "alice")
        let b = ChannelParticipant(cardId: "card_B", handle: "bob")
        let msg = try await store.sendDirectMessage(from: a, to: b, body: "pic", imagePaths: [srcPath])
        #expect(msg.imagePaths?.count == 1)
        let msgs = await store.loadDMMessages(between: a, and: b)
        #expect(msgs.first(where: { $0.id == msg.id })?.imagePaths == msg.imagePaths)
    }

    @Test func readStateRoundTrip() async throws {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)

        // Save ids, load back — verifies id-based read-state survives disk hop.
        // Regression guard for iteration 9 rewrite: if the JSON shape drifts,
        // users will see channels "become unread again" after restart.
        let saved = ChannelsStore.ReadState(
            channels: ["general": "msg_abc", "coord": "msg_xyz"],
            dms: ["card_A__card_B": "msg_dm1"]
        )
        try await store.saveReadState(saved)
        let loaded = await store.loadReadState()
        #expect(loaded.channels["general"] == "msg_abc")
        #expect(loaded.channels["coord"] == "msg_xyz")
        #expect(loaded.dms["card_A__card_B"] == "msg_dm1")
    }

    @Test func draftsRoundTrip() async throws {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)

        // Regression guard for iteration 9: if drafts don't survive a round-trip
        // through disk, the user loses typing across app restart.
        let saved = ChannelsStore.DraftsState(
            channels: ["coord": "hey team"],
            dms: ["card_A__card_B": "secret sauce"]
        )
        try await store.saveDrafts(saved)
        let loaded = await store.loadDrafts()
        #expect(loaded.channels["coord"] == "hey team")
        #expect(loaded.dms["card_A__card_B"] == "secret sauce")
    }

    @Test func loadReadStateReturnsEmptyWhenFileMissing() async {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)
        let loaded = await store.loadReadState()
        #expect(loaded.channels.isEmpty)
        #expect(loaded.dms.isEmpty)
    }

    @Test func loadDraftsReturnsEmptyWhenFileMissing() async {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)
        let loaded = await store.loadDrafts()
        #expect(loaded.channels.isEmpty)
        #expect(loaded.dms.isEmpty)
    }

    @Test func userlikeParticipantKey() async throws {
        let base = tmpBase()
        defer { try? FileManager.default.removeItem(atPath: base) }
        let store = ChannelsStore(baseDir: base)
        let userA = ChannelParticipant(cardId: nil, handle: "rchaves")
        let userB = ChannelParticipant(cardId: nil, handle: "alice")
        let p = await store.dmLogPath(partyA: userA, partyB: userB)
        #expect(p.contains("@alice"))
        #expect(p.contains("@rchaves"))
    }
}
