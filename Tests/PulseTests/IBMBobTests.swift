import Foundation
import Testing
@testable import Pulse

/// Answers as IBM Bob would, and writes down every host a key was sent to.
private final class IBMBobStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hosts: [String: [String]] = [:]
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "Authorization") ?? ""
        Self.lock.withLock { Self.hosts[key, default: []].append(request.url?.host ?? "") }
        let path = request.url?.path ?? ""
        let (status, body): (Int, Data) = switch (key, path) {
        case ("Apikey refused", _): (401, Data())
        case ("Apikey evil", "/admin/v1/profile"):
            (200, Data(#"{"instances":[{"instance_id":"i","user_id":"u","region_domain":"evil.example","teams":[{"id":"t"}]}]}"#.utf8))
        case ("Apikey none", "/admin/v1/profile"): (200, Data(#"{"instances":[]}"#.utf8))
        case (_, "/admin/v1/profile"): (200, IBMBobTests.profile)
        case (_, "/admin/v1/teams/team-one/users/user-one"): (200, Data(#"{"usage":10}"#.utf8))
        case (_, "/admin/v1/teams/team-two/users/user-two"): (200, Data(#"{"usage":25,"budget_limit":160}"#.utf8))
        default: (404, Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// IBM Bob's Bobcoin budgets.
///
/// **The fixtures are second-hand**: written from CodexBar's IBM Bob provider
/// and its tests (MIT), not captured from a live account. They pin the shape
/// Pulse reads; they do not prove the shape is right.
@Suite("IBM Bob")
struct IBMBobTests {
    static let profile: Data = {
        let url = Bundle.module.url(forResource: "ibm-bob-profile", withExtension: "json", subdirectory: "Fixtures")!
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    private let context = ProfileContext(provider: .ibmBob, credential: "k", serverAddress: nil)

    private func fetch(key: String) async -> ProviderUsage {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IBMBobStub.self]
        let context = ProfileContext(provider: .ibmBob, credential: key, serverAddress: nil)
        return await IBMBobUsageService.fetch(context, session: URLSession(configuration: configuration))
    }

    private func hosts(for key: String) -> [String] {
        IBMBobStub.lock.withLock { IBMBobStub.hosts["Apikey \(key)"] ?? [] }
    }

    @Test("Every team's Bobcoins against every team's budget, from each team's own region")
    func teams() async throws {
        let usage = await fetch(key: "fixture")

        #expect(usage.state == .live)
        #expect(usage.account == AccountKey(.ibmBob))
        let window = try #require(usage.windows.first)
        #expect(usage.windows.count == 1)
        #expect(window.kind == .monthly)
        #expect(window.usedFraction == 35.0 / 200.0)
        // A billing month: a sort key, not a stated length.
        #expect(!window.reportsLength)
        // The sooner of the two subscriptions' refreshes.
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_790_812_800))
        #expect(usage.plan == "Enterprise, Pro+")
        #expect(hosts(for: "fixture") == ["api.us-east.bob.ibm.com", "api.us-east.bob.ibm.com", "api.eu-de.bob.ibm.com"])
    }

    @Test("A team without a budget is unlimited, and nothing is made up for it")
    func unlimitedTeam() {
        let teams = [
            IBMBobUsageService.Team(used: 10, budget: 40, plan: "Pro+", resetsAt: nil),
            IBMBobUsageService.Team(used: 25, budget: nil, plan: "Enterprise", resetsAt: nil),
        ]
        #expect(IBMBobUsageService.reading(teams, context: context).state == .unavailable(.noLimitsReported))
    }

    @Test("Figures that aren't figures are left off, and nothing left is no limits", arguments: [
        [IBMBobUsageService.Team(used: -1, budget: 40, plan: nil, resetsAt: nil)],
        [IBMBobUsageService.Team(used: 5, budget: 0, plan: nil, resetsAt: nil)],
        [IBMBobUsageService.Team(used: 5, budget: -40, plan: nil, resetsAt: nil)],
    ])
    func noFigures(teams: [IBMBobUsageService.Team]) {
        #expect(IBMBobUsageService.reading(teams, context: context).state == .unavailable(.noLimitsReported))
    }

    @Test("A key that sees no subscription has no plan")
    func noSubscription() async {
        #expect(await fetch(key: "none").state == .unavailable(.noPlan))
    }

    @Test("A region outside bob.ibm.com is refused before the key is sent there")
    func untrustedRegion() async {
        #expect(await fetch(key: "evil").state == .unavailable(.unreadableReply))
        #expect(hosts(for: "evil") == ["api.us-east.bob.ibm.com"])
    }

    @Test("Regional hosts", arguments: [
        ("us-east.bob.ibm.com", "https://api.us-east.bob.ibm.com"),
        ("api.eu-de.bob.ibm.com", "https://api.eu-de.bob.ibm.com"),
        (nil, "https://api.us-east.bob.ibm.com"),
    ] as [(String?, String)])
    func regions(domain: String?, url: String) {
        #expect(IBMBobUsageService.regionalHost(domain)?.absoluteString == url)
    }

    @Test("Hosts that only look like IBM's", arguments: [
        "evil.example/x.bob.ibm.com", "bob.ibm.com.evil.example", "x@evil.example",
        "evil.example?next=.bob.ibm.com", "evil.example#.bob.ibm.com",
        "evil.example@us-east.bob.ibm.com", "us-east.bob.ibm.com:443",
    ])
    func impostors(domain: String) {
        #expect(IBMBobUsageService.regionalHost(domain) == nil)
    }

    @Test("A refused key is refused")
    func refused() async {
        #expect(await fetch(key: "refused").state == .unavailable(.apiKeyRefused))
    }

    @Test("No key is asked for, not sent")
    func missingKey() async {
        let empty = ProfileContext(provider: .ibmBob, credential: " ", serverAddress: nil)
        #expect(await IBMBobUsageService.fetch(empty).state == .unavailable(.apiKeyMissing))
    }

    @Test("A key is sent as an IBM API key, a Bob sign-in's JWT as a bearer token")
    func authorization() {
        #expect(IBMBobUsageService.authorization("plain-key") == "Apikey plain-key")
        let jwt = "header.eyJzdWIiOiJ1c2VyIn0.signature"
        #expect(IBMBobUsageService.authorization(jwt) == "Bearer \(jwt)")
    }
}
