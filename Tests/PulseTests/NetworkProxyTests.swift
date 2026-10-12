import Foundation
import Testing
@testable import Pulse

@Suite("Network proxy")
struct NetworkProxyTests {
    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let (defaults, cleanup) = TestDefaults.make("networkProxy")
        defer { cleanup() }
        try body(defaults)
    }

    @Test("An upgrade keeps following the system")
    func defaultFollowsSystem() {
        withIsolatedDefaults { defaults in
            #expect(AppSettings.storedNetworkProxy(in: defaults) == .default)
            #expect(NetworkProxySettings.default.mode == .system)
            #expect(NetworkSession.configured(.ephemeral, for: .default).proxyConfigurations.isEmpty)
        }
    }

    @Test("Every offered manual proxy survives a round trip")
    func manualProxyRoundTrips() {
        withIsolatedDefaults { defaults in
            for kind in NetworkProxyKind.allCases {
                let settings = NetworkProxySettings(
                    mode: .manual,
                    kind: kind,
                    host: "127.0.0.1",
                    port: 7_897
                )
                AppSettings.storeNetworkProxy(settings, in: defaults)
                #expect(AppSettings.storedNetworkProxy(in: defaults) == settings)
                #expect(NetworkSession.configured(.ephemeral, for: settings).proxyConfigurations.count == 1)
            }
        }
    }

    @Test("Unreadable storage falls back to the system")
    func unreadableStorageFallsBack() {
        withIsolatedDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: AppSettings.networkProxyDefaultsKey)
            #expect(AppSettings.storedNetworkProxy(in: defaults) == .default)
        }
    }

    @Test("Host and port validation refuses incomplete endpoints", arguments: [
        ("", "7897", false),
        ("   ", "7897", false),
        ("127.0.0.1", "0", false),
        ("127.0.0.1", "65536", false),
        ("127.0.0.1", "1.5", false),
        (" proxy.local ", " 443 ", true)
    ])
    func endpointValidation(host: String, port: String, valid: Bool) {
        let parsedHost = NetworkProxySettings.validHost(host)
        let parsedPort = NetworkProxySettings.validPort(port)
        #expect((parsedHost != nil && parsedPort != nil) == valid)
    }

    @Test("HTTP helpers receive only the chosen proxy")
    func httpProcessEnvironment() throws {
        let settings = NetworkProxySettings(mode: .manual, kind: .http, host: "proxy.local", port: 8_080)
        let environment = try #require(settings.processEnvironment(over: [
            "PATH": "/usr/bin",
            "ALL_PROXY": "socks5://old:1",
            "https_proxy": "http://old:2"
        ]))

        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["HTTP_PROXY"] == "http://proxy.local:8080")
        #expect(environment["HTTPS_PROXY"] == "http://proxy.local:8080")
        #expect(environment["ALL_PROXY"] == nil)
        #expect(environment["https_proxy"] == nil)
        #expect(environment["NO_PROXY"] == "localhost,127.0.0.1,::1")
    }

    @Test("SOCKS helpers receive ALL_PROXY and bracket an IPv6 host")
    func socksProcessEnvironment() throws {
        let settings = NetworkProxySettings(mode: .manual, kind: .socks5, host: "::1", port: 1_080)
        let environment = try #require(settings.processEnvironment(over: [
            "HTTP_PROXY": "http://old:1",
            "HTTPS_PROXY": "http://old:1"
        ]))

        #expect(environment["ALL_PROXY"] == "socks5://[::1]:1080")
        #expect(environment["HTTP_PROXY"] == nil)
        #expect(environment["HTTPS_PROXY"] == nil)
        #expect(environment["NO_PROXY"] == "localhost,127.0.0.1,::1")
    }

    @Test("Following the system does not replace a helper's environment")
    func systemProcessEnvironmentIsInherited() {
        #expect(NetworkProxySettings.default.processEnvironment(over: ["HTTPS_PROXY": "http://shell:9"]) == nil)
        #expect(NetworkSession.configured(.ephemeral, for: .default).connectionProxyDictionary == nil)
    }

    @Test("No proxy turns the system's off for requests and survives a round trip")
    func directSession() {
        withIsolatedDefaults { defaults in
            // A saved endpoint stays saved, ready for the custom proxy again.
            let settings = NetworkProxySettings(mode: .direct, kind: .http, host: "127.0.0.1", port: 7_897)
            AppSettings.storeNetworkProxy(settings, in: defaults)
            #expect(AppSettings.storedNetworkProxy(in: defaults) == settings)
            #expect(settings.endpoint == nil)

            let configuration = NetworkSession.configured(.ephemeral, for: settings)
            #expect(configuration.proxyConfigurations.isEmpty)
            // Empty, not nil: nil is the system's proxy.
            let dictionary = configuration.connectionProxyDictionary
            #expect(dictionary != nil)
            #expect(dictionary?.isEmpty == true)
        }
    }

    @Test("No proxy clears every proxy a helper would inherit, and nothing else")
    func directProcessEnvironment() throws {
        let settings = NetworkProxySettings(mode: .direct, kind: .socks5, host: "proxy.local", port: 1_080)
        let environment = try #require(settings.processEnvironment(over: [
            "PATH": "/usr/bin",
            "HTTP_PROXY": "http://shell:1", "https_proxy": "http://shell:2",
            "ALL_PROXY": "socks5://shell:3", "no_proxy": "example.com"
        ]))
        #expect(environment == ["PATH": "/usr/bin"])
    }

    @Test("Follow System stays the default, and System Proxy Only survives a round trip")
    func systemRequiredRoundTrip() {
        withIsolatedDefaults { defaults in
            #expect(NetworkProxySettings.default.mode == .system)
            let settings = NetworkProxySettings(mode: .systemRequired, kind: .http, host: "", port: nil)
            AppSettings.storeNetworkProxy(settings, in: defaults)
            #expect(AppSettings.storedNetworkProxy(in: defaults) == settings)
            // The system's proxy, as Follow System has it: nothing set here.
            let configuration = NetworkSession.configured(.ephemeral, for: settings)
            #expect(configuration.connectionProxyDictionary == nil)
            #expect(configuration.proxyConfigurations.isEmpty)
        }
    }

    @Test("Every session Pulse makes carries the guard, whatever the setting")
    func guardInstalled() {
        for mode in NetworkProxyMode.allCases {
            let settings = NetworkProxySettings(mode: mode, kind: .http, host: "127.0.0.1", port: 7_897)
            let classes = NetworkSession.configured(.ephemeral, for: settings).protocolClasses ?? []
            #expect(classes.first == ProxyGuard.self)
        }
    }

    @Test("Only System Proxy Only with nothing switched on refuses, and never loopback", arguments: [
        (NetworkProxyMode.systemRequired, false, "https://api.anthropic.com/x", true),
        (.systemRequired, true, "https://api.anthropic.com/x", false),
        (.systemRequired, false, "http://127.0.0.1:4000/v1", false),
        (.systemRequired, false, "http://localhost:4000/v1", false),
        (.systemRequired, false, "http://[::1]:4000/v1", false),
        (.system, false, "https://api.anthropic.com/x", false),
        (.direct, false, "https://api.anthropic.com/x", false),
        (.manual, false, "https://api.anthropic.com/x", false),
    ])
    func refusal(mode: NetworkProxyMode, systemOn: Bool, url: String, refused: Bool) {
        let settings = NetworkProxySettings(mode: mode, kind: .http, host: "127.0.0.1", port: 7_897)
        #expect(NetworkSession.refuses(URL(string: url), settings: settings, systemProxyOn: { systemOn }) == refused)
    }

    @Test("A proxy counts as on when any of macOS's switches is")
    func systemProxySwitches() {
        #expect(!SystemProxy.isOn(in: [:]))
        #expect(!SystemProxy.isOn(in: ["HTTPEnable": 0, "HTTPSEnable": 0, "ExceptionsList": ["*.local"]]))
        for key in ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable", "ProxyAutoDiscoveryEnable"] {
            #expect(SystemProxy.isOn(in: [key: 1]), "\(key)")
        }
    }

    @Test("System Proxy Only leaves a helper's environment alone, like Follow System")
    func systemRequiredProcessEnvironment() {
        let settings = NetworkProxySettings(mode: .systemRequired, kind: .http, host: "", port: nil)
        #expect(settings.processEnvironment(over: ["HTTPS_PROXY": "http://shell:9"]) == nil)
    }

    @MainActor
    @Test("A refused request reads as the proxy being off, and nothing else is renamed")
    func heldBackReason() {
        let account = AccountKey(.claudeCode)
        let unreachable = ProviderUsage.unavailable(account, reason: .unreachable)
        #expect(UsageStore.namingHeldBack(unreachable, isHoldingBack: true).state == .unavailable(.systemProxyOff))
        #expect(UsageStore.namingHeldBack(unreachable, isHoldingBack: false).state == .unavailable(.unreachable))
        let signIn = ProviderUsage.unavailable(account, reason: .claudeSignInRequired)
        #expect(UsageStore.namingHeldBack(signIn, isHoldingBack: true).state == .unavailable(.claudeSignInRequired))
        // Quitting the proxy app is not an outage to announce.
        #expect(AlertMemory.standing(of: .systemProxyOff) == .neutral)
    }

    @Test("Loopback is an address, not a name that starts like one", arguments: [
        ("localhost", true), ("api.localhost", true), ("127.0.0.1", true), ("127.8.9.10", true),
        ("::1", true), ("[::1]", true),
        ("127.audit.example.com", false), ("127.0.0.1.example.com", false), ("128.0.0.1", false),
        ("api.anthropic.com", false), ("::2", false),
    ])
    func loopback(host: String, isLoopback: Bool) {
        #expect(NetworkSession.isLoopback(host) == isLoopback)
    }
}
