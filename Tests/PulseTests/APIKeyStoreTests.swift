import Foundation
import Testing
@testable import Pulse

/// The key store's writes, in a temporary folder: never this Mac's own keys.
struct APIKeyStoreTests {
    private func withFolder(_ body: (URL) throws -> Void) rethrows {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PulseTests.keys.\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    @Test func savesAtOnceKeepEveryKey() async {
        // Each save reads the whole file and writes it back; without the lock
        // a later write put back the file from before an earlier one's change.
        let folder = FileManager.default.temporaryDirectory.appending(path: "PulseTests.keys.\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let providers: [Provider] = Array(Provider.builtIn.prefix(8))
        await withTaskGroup(of: Void.self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { APIKeyStore.setKey("key-\(index)", for: provider, in: folder) }
                group.addTask { APIKeyStore.setKey("slot-\(index)", for: provider, slot: "console", in: folder) }
            }
        }
        for (index, provider) in providers.enumerated() {
            #expect(APIKeyStore.key(for: provider, in: folder) == "key-\(index)")
            #expect(APIKeyStore.key(for: provider, slot: "console", in: folder) == "slot-\(index)")
        }
    }

    @Test func aRenewalReplacesOnlyTheCredentialItRenewed() {
        withFolder { folder in
            APIKeyStore.setKey("old", for: .deepSeek, slot: "console", in: folder)
            #expect(APIKeyStore.replaceKey("old", with: "new", for: .deepSeek, slot: "console", in: folder))
            #expect(APIKeyStore.key(for: .deepSeek, slot: "console", in: folder) == "new")
        }
    }

    @Test func aRemovedCredentialStaysRemoved() {
        withFolder { folder in
            APIKeyStore.setKey("old", for: .deepSeek, slot: "console", in: folder)
            // Removed in Settings while the renewal was reading the browser.
            APIKeyStore.setKey(nil, for: .deepSeek, slot: "console", in: folder)
            #expect(!APIKeyStore.replaceKey("old", with: "new", for: .deepSeek, slot: "console", in: folder))
            #expect(APIKeyStore.key(for: .deepSeek, slot: "console", in: folder) == nil)
        }
    }

    @Test func aCredentialSavedMeanwhileIsNotWrittenOver() {
        withFolder { folder in
            APIKeyStore.setKey("old", for: .deepSeek, slot: "console", in: folder)
            APIKeyStore.setKey("typed", for: .deepSeek, slot: "console", in: folder)
            #expect(!APIKeyStore.replaceKey("old", with: "new", for: .deepSeek, slot: "console", in: folder))
            #expect(APIKeyStore.key(for: .deepSeek, slot: "console", in: folder) == "typed")
        }
    }
}
