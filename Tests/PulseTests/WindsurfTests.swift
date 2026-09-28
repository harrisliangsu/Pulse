import Foundation
import Testing
@testable import Pulse

/// Windsurf's plan status, from windsurf.com's GetPlanStatus over protobuf.
///
/// **The fixture is second-hand**: a reply built from the field numbers in
/// CodexBar's Windsurf provider and the values in its tests (MIT), not
/// captured from a live account. It pins the shape Pulse reads; it does not
/// prove the shape is right.
@Suite("Windsurf")
struct WindsurfTests {
    private let context = ProfileContext(provider: .windsurf, credential: "{}", serverAddress: nil)
    private let session = #"{"devin_session_token":"devin-session-token$abc","devin_auth1_token":"auth1_xyz","#
        + #""devin_account_id":"account-123","devin_primary_org_id":"org-456"}"#

    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "windsurf-plan-status", withExtension: "json",
                                                 subdirectory: "Fixtures"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try #require((object?["base64"] as? String).flatMap { Data(base64Encoded: $0) })
    }

    /// A reply with a `plan_status` of the given varint fields, for the cases
    /// the fixture doesn't cover.
    private func reply(_ fields: [(Int, UInt64)]) -> Data {
        var status = Data()
        for (number, value) in fields {
            WindsurfProtobuf.appendKey(number, wire: 0, to: &status)
            WindsurfProtobuf.appendVarint(value, to: &status)
        }
        var reply = Data()
        WindsurfProtobuf.appendKey(1, wire: 2, to: &reply)
        WindsurfProtobuf.appendVarint(UInt64(status.count), to: &reply)
        reply.append(status)
        return reply
    }

    @Test("Daily and weekly are read as used = 100 − remaining, with their stated resets")
    func planStatus() throws {
        let usage = WindsurfUsageService.reading(from: try fixture(), context: context)

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.windsurf))
        #expect(usage.plan == "Pro")
        #expect(usage.windows.map(\.kind) == [.daily, .weekly])
        #expect(usage.windows.map(\.usedFraction) == [0.32, 0.16])
        #expect(usage.windows.map(\.resetsAt) == [
            Date(timeIntervalSince1970: 1_777_900_000), Date(timeIntervalSince1970: 1_778_000_000),
        ])
        // "Daily" and "weekly" are the service naming the lengths.
        #expect(usage.windows.allSatisfy { $0.reportsLength })
    }

    @Test("Fields this doesn't read — a fixed-width one included — are skipped, not fatal")
    func skipsUnknown() throws {
        let status = try #require(WindsurfUsageService.planStatus(from: try fixture()))
        #expect(status.dailyRemaining == 68)
        #expect(status.weeklyRemaining == 84)
    }

    @Test("A quota protobuf left out is left off: it could be spent, or not on the plan")
    func absentQuota() {
        let usage = WindsurfUsageService.reading(from: reply([(15, 40), (18, 1_778_000_000)]), context: context)
        #expect(usage.windows.map(\.kind) == [.weekly])
        #expect(usage.windows.first?.usedFraction == 0.6)
    }

    @Test("A figure over 100 is not a percentage, and nothing left is no limits")
    func noFigures() {
        let usage = WindsurfUsageService.reading(from: reply([(14, 250)]), context: context)
        #expect(usage.state == .unavailable(.noLimitsReported))
    }

    @Test("A reply that can't be read", arguments: [
        Data(), Data("not protobuf at all".utf8), Data([0x0A, 0x05, 0x70]), Data([0x08, 0x01]),
    ])
    func unreadable(data: Data) {
        #expect(WindsurfUsageService.reading(from: data, context: context).state == .unavailable(.unreadableReply))
    }

    // MARK: - The session

    @Test("The pasted session is the four devin_* values")
    func pastedSession() throws {
        let parsed = try #require(WindsurfUsageService.Session(pasted: session))
        #expect(parsed.token == "devin-session-token$abc")
        #expect(parsed.auth1 == "auth1_xyz")
        #expect(parsed.accountID == "account-123")
        #expect(parsed.organizationID == "org-456")
    }

    @Test("Anything short of all four is no session", arguments: [
        #"{"devin_session_token":"t","devin_auth1_token":"a","devin_account_id":"c"}"#,
        #"{"devin_session_token":"t","devin_auth1_token":"a","devin_account_id":"c","devin_primary_org_id":" "}"#,
        "devin_session_token=t",
        "[]",
    ])
    func incompleteSession(text: String) {
        #expect(WindsurfUsageService.Session(pasted: text) == nil)
    }

    @Test("The request carries the session in the headers windsurf.com expects, and in the body")
    func request() throws {
        let parsed = try #require(WindsurfUsageService.Session(pasted: session))
        let request = WindsurfUsageService.request(parsed)

        #expect(request.url?.host == "windsurf.com")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval <= 15)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/proto")
        #expect(request.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(request.value(forHTTPHeaderField: "x-auth-token") == "devin-session-token$abc")
        #expect(request.value(forHTTPHeaderField: "x-devin-auth1-token") == "auth1_xyz")
        #expect(request.value(forHTTPHeaderField: "x-devin-account-id") == "account-123")
        #expect(request.value(forHTTPHeaderField: "x-devin-primary-org-id") == "org-456")

        var body = WindsurfProtobuf.Reader(try #require(request.httpBody))
        #expect(body.next()?.value == .bytes(Data("devin-session-token$abc".utf8)))
        #expect(body.next()?.value == .varint(1))
        #expect(body.next() == nil)
        #expect(body.isComplete)
    }

    @Test("No session is asked for, not sent")
    func missingSession() async {
        let empty = ProfileContext(provider: .windsurf, credential: "  ", serverAddress: nil)
        #expect(await WindsurfUsageService.fetch(empty).state == .unavailable(.sessionMissing))
    }

    @Test("A saved credential that isn't the four values is never sent")
    func unusableSession() async {
        let wrong = ProfileContext(provider: .windsurf, credential: "sk-not-a-session", serverAddress: nil)
        #expect(await WindsurfUsageService.fetch(wrong).state == .unavailable(.sessionMissing))
    }

    @Test("What Read saves from the browser is what the session reads, quoted values unwrapped")
    func fromBrowserStorage() throws {
        let stored = [
            "devin_session_token": "\"session-token-value\"",
            "devin_auth1_token": "auth1-token-value",
            "devin_account_id": "\"account-1\"",
            "devin_primary_org_id": "org-1",
            "unrelated": "kept out",
        ]
        let credential = try #require(ProviderProfile.storageCredential(from: stored, keys: WindsurfUsageService.storageKeys))
        #expect(!credential.contains("unrelated"))
        let session = try #require(WindsurfUsageService.Session(pasted: credential))
        #expect(session.token == "session-token-value")
        #expect(session.accountID == "account-1")
        var partial = stored
        partial["devin_primary_org_id"] = nil
        #expect(ProviderProfile.storageCredential(from: partial, keys: WindsurfUsageService.storageKeys) == nil)
    }

    @Test("A refused or redirected session reads as expired", arguments: [401, 403, 302])
    func refused(status: Int) {
        #expect(ProfileHTTP.classify(.init(data: Data(), status: status), refused: .sessionExpired) == .failure(.sessionExpired))
    }
}
