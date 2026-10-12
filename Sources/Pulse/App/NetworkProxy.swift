// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation
import CFNetwork
import Network
import os

enum NetworkProxyMode: String, CaseIterable, Codable, Identifiable, Sendable {
    /// No proxy at all, whatever macOS or the shell says.
    case direct
    /// macOS's proxy settings, or directly when macOS has none. The default,
    /// and what every installation did before this setting existed.
    case system
    /// macOS's proxy settings, and **no connection at all** when macOS has
    /// none switched on — for someone whose accounts must never be reached
    /// from this Mac's own address, and whose proxy app can be quit.
    case systemRequired
    /// A proxy for Pulse only.
    case manual

    var id: Self { self }

    var title: String {
        switch self {
        case .direct: .localized("No Proxy")
        case .system: .localized("Follow System")
        case .systemRequired: .localized("System Proxy Only")
        case .manual: .localized("Custom Proxy")
        }
    }

    /// What the choice does, under the picker.
    var explanation: String {
        switch self {
        case .direct: .localized("Pulse connects directly and ignores the proxy in macOS settings.")
        case .system: .localized("Uses the proxy in macOS settings, or connects directly when there is none.")
        case .systemRequired: .localized("Uses the proxy in macOS settings, and doesn't connect when there is none.")
        case .manual: .localized("A proxy for Pulse only.")
        }
    }
}

/// Whether macOS has a proxy switched on, read from its current settings.
enum SystemProxy {
    /// Any of the HTTP, HTTPS or SOCKS proxies, or automatic configuration —
    /// a PAC file or discovery. A PAC file may still send a host directly;
    /// that is its own rule, the proxy app's, and not a direct connection
    /// Pulse chose.
    static func isOn(in settings: [String: Any]) -> Bool {
        let switches = [
            kCFNetworkProxiesHTTPEnable as String,
            kCFNetworkProxiesHTTPSEnable as String,
            kCFNetworkProxiesSOCKSEnable as String,
            kCFNetworkProxiesProxyAutoConfigEnable as String,
            "ProxyAutoDiscoveryEnable",
        ]
        return switches.contains { (settings[$0] as? NSNumber)?.boolValue == true }
    }

    static var isOn: Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return false
        }
        return isOn(in: settings)
    }
}

enum NetworkProxyKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case http
    case socks5

    var id: Self { self }

    var title: String {
        switch self {
        case .http: .localized("HTTP")
        case .socks5: .localized("SOCKS5")
        }
    }
}

/// The proxy Pulse applies to its own requests and supported helper processes.
struct NetworkProxySettings: Codable, Equatable, Sendable {
    var mode: NetworkProxyMode
    var kind: NetworkProxyKind
    var host: String
    var port: Int?

    static let `default` = NetworkProxySettings(mode: .system, kind: .http, host: "", port: nil)

    var endpoint: (host: String, port: UInt16)? {
        guard mode == .manual,
              let host = Self.validHost(host),
              let port,
              (1...65_535).contains(port)
        else { return nil }
        return (host, UInt16(port))
    }

    static func validHost(_ value: String) -> String? {
        let host = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? nil : host
    }

    static func validPort(_ value: String) -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(text), (1...65_535).contains(port) else { return nil }
        return port
    }

    /// A complete environment rather than only the added keys, because setting
    /// `Process.environment` replaces what the child would otherwise inherit.
    /// Nil leaves the inherited one alone, which is what following the system
    /// means for a child.
    ///
    /// **No proxy clears the shell's too.** A helper launched from a terminal
    /// inherits whatever proxy that shell exported, and "no proxy" that still
    /// sent a helper through one would be the setting not doing what it says.
    func processEnvironment(over base: [String: String]) -> [String: String]? {
        var environment = base
        switch mode {
        // Helpers are not held to "System Proxy Only": what they inherit is
        // what they inherited before there was a choice.
        case .system, .systemRequired:
            return nil
        case .direct:
            Self.removeProxies(from: &environment)
            return environment
        case .manual:
            break
        }
        guard let endpoint else { return nil }
        Self.removeProxies(from: &environment)

        let host = endpoint.host.contains(":") && !endpoint.host.hasPrefix("[")
            ? "[\(endpoint.host)]"
            : endpoint.host
        switch kind {
        case .http:
            let proxy = "http://\(host):\(endpoint.port)"
            environment["HTTP_PROXY"] = proxy
            environment["HTTPS_PROXY"] = proxy
        case .socks5:
            environment["ALL_PROXY"] = "socks5://\(host):\(endpoint.port)"
        }
        environment["NO_PROXY"] = "localhost,127.0.0.1,::1"
        return environment
    }

    private static func removeProxies(from environment: inout [String: String]) {
        for key in [
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy"
        ] {
            environment.removeValue(forKey: key)
        }
    }
}

/// Owns the session configuration for every non-loopback HTTP request Pulse
/// makes. Antigravity deliberately keeps its local language-server session.
enum NetworkSession {
    private struct State {
        var settings = NetworkProxySettings.default
        var session = URLSession(configuration: NetworkSession.configured(.default, for: .default))
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static var shared: URLSession {
        state.withLock { $0.session }
    }

    static var currentSettings: NetworkProxySettings {
        state.withLock { $0.settings }
    }

    static func apply(_ settings: NetworkProxySettings) {
        let configuration = configured(.default, for: settings)
        let replacement = URLSession(configuration: configuration)
        let (changed, previous) = state.withLock { state in
            guard state.settings != settings else { return (false, state.session) }
            let previous = state.session
            state.settings = settings
            state.session = replacement
            return (true, previous)
        }

        if changed {
            previous.invalidateAndCancel()
        } else {
            replacement.invalidateAndCancel()
        }
    }

    /// Adds the current proxy to a caller's cookie/cache/timeout choices.
    static func configured(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        configured(configuration, for: state.withLock { $0.settings })
    }

    /// Whether a request to `url` is refused rather than sent: "System Proxy
    /// Only" with no proxy switched on in macOS. This Mac's own loopback
    /// addresses are never refused — nothing leaves the machine.
    static func refuses(_ url: URL?, settings: NetworkProxySettings, systemProxyOn: () -> Bool) -> Bool {
        guard settings.mode == .systemRequired else { return false }
        if let host = url?.host(), isLoopback(host) { return false }
        return !systemProxyOn()
    }

    /// `localhost`, a name under it, `::1`, or an IPv4 address in
    /// 127.0.0.0/8 — parsed as an address, so `127.example.com` is a public
    /// name like any other and is held back with the rest.
    static func isLoopback(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".localhost") { return true }
        if let v6 = IPv6Address(host) { return v6 == .loopback }
        if let v4 = IPv4Address(host) { return v4.rawValue.first == 127 }
        return false
    }

    /// "System Proxy Only" is refusing everything right now.
    static var isHoldingBack: Bool {
        refuses(nil, settings: currentSettings, systemProxyOn: { SystemProxy.isOn })
    }

    static func subprocessEnvironment() -> [String: String]? {
        state.withLock { $0.settings }.processEnvironment(over: ProcessInfo.processInfo.environment)
    }

    // Internal so `NetworkProxyTests` can prove the direct/system/manual boundary
    // without making a real network request.
    static func configured(
        _ configuration: URLSessionConfiguration,
        for settings: NetworkProxySettings
    ) -> URLSessionConfiguration {
        // Every session, whatever the setting it was made under: the guard
        // reads the setting at each request, so a session a caller kept from
        // before a change is held to the new one too.
        configuration.protocolClasses = [ProxyGuard.self] + (configuration.protocolClasses ?? [])
        // An empty dictionary is "no proxy"; nil, the default, is the system's.
        if settings.mode == .direct {
            configuration.proxyConfigurations = []
            configuration.connectionProxyDictionary = [:]
            return configuration
        }
        guard let endpoint = settings.endpoint,
              let port = NWEndpoint.Port(rawValue: endpoint.port)
        else { return configuration }

        let target = NWEndpoint.hostPort(host: NWEndpoint.Host(endpoint.host), port: port)
        switch settings.kind {
        case .http:
            configuration.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: target)]
        case .socks5:
            configuration.proxyConfigurations = [ProxyConfiguration(socksv5Proxy: target)]
        }
        return configuration
    }
}

/// Fails a request instead of sending it while "System Proxy Only" has no
/// proxy to use, so nothing goes out from this Mac's own address. Answers
/// only the requests it refuses; every other one is left to URLSession.
final class ProxyGuard: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        NetworkSession.refuses(request.url, settings: NetworkSession.currentSettings, systemProxyOn: { SystemProxy.isOn })
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
