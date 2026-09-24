import Foundation
import Testing
@testable import Pulse

/// The one place in Pulse where a reader types a host and a credential is then
/// sent to it. These are not parsing tests — they are about **where a key is
/// allowed to go**, which is why they are exhaustive about the near misses
/// rather than about the happy path.
@Suite("Gateway address")
struct GatewayAddressTests {
    // MARK: - Scheme

    /// The whole point: a key goes to the host the reader named, over a
    /// channel nobody can read.
    @Test("A bare host becomes https")
    func bareHostBecomesHTTPS() throws {
        let url = try #require(GatewayAddress.url(from: "gateway.example.com", path: "/v1/usage"))
        #expect(url.absoluteString == "https://gateway.example.com/v1/usage")
    }

    /// **Refused, not upgraded.** Rewriting somebody's http address to https
    /// would send the key somewhere they did not type, and a rewrite that
    /// fails looks like the server being down rather than like a rule.
    @Test("Plain http to a public host is refused rather than upgraded")
    func publicHTTPIsRefused() {
        #expect(GatewayAddress.url(from: "http://gateway.example.com", path: "/x") == nil)
        #expect(!GatewayAddress.isUsable("http://gateway.example.com"))
    }

    /// A gateway on the reader's own machine or LAN has nothing between it and
    /// Pulse to intercept anything, and requiring a certificate there would
    /// rule out the ordinary way people run these.
    @Test("Plain http is allowed on a private network")
    func privateHTTPIsAllowed() throws {
        for host in [
            "localhost", "127.0.0.1", "10.0.0.5", "192.168.1.9",
            "172.16.0.1", "172.31.255.254", "169.254.1.1", "nas.local",
        ] {
            let url = try #require(
                GatewayAddress.url(from: "http://\(host):8080", path: "/x"), "\(host)"
            )
            #expect(url.scheme == "http", "\(host)")
        }
    }

    /// The near misses either side of the RFC 1918 block, which a range
    /// written by hand gets wrong in exactly this place.
    @Test("Hosts just outside the private ranges are not private")
    func neighboursOfPrivateRangesAreRefused() {
        for host in ["172.15.0.1", "172.32.0.1", "11.0.0.1", "192.169.0.1", "169.255.0.1"] {
            #expect(!GatewayAddress.allowsPlainHTTP(host), "\(host)")
        }
    }

    /// The colon test is what separates an IPv6 literal from a *name* that
    /// happens to start with the same two letters — and `fdn.example.com` is a
    /// perfectly ordinary public host.
    @Test("A hostname beginning fc, fd or fe80 is not an IPv6 private address")
    func ipv6PrefixesDoNotMatchNames() {
        #expect(GatewayAddress.allowsPlainHTTP("fd00::1"))
        #expect(GatewayAddress.allowsPlainHTTP("fe80::1"))
        #expect(!GatewayAddress.allowsPlainHTTP("fd00.example.com"))
        #expect(!GatewayAddress.allowsPlainHTTP("fcgateway.example.com"))
    }

    // MARK: - Misleading URLs

    /// Both are ways of writing a URL whose real host is not where the eye
    /// lands, and a query is a second thing being sent that nobody asked for.
    @Test("User info, a fragment and a query are all refused")
    func misleadingURLsAreRefused() {
        #expect(GatewayAddress.url(from: "https://user:pw@evil.example/", path: "/x") == nil)
        #expect(GatewayAddress.url(from: "https://gateway.example.com/#@evil", path: "/x") == nil)
        #expect(GatewayAddress.url(from: "https://gateway.example.com/?token=x", path: "/x") == nil)
    }

    @Test("Anything that is not an http address is refused")
    func nonHTTPSchemesAreRefused() {
        for typed in ["file:///etc/passwd", "ftp://example.com", "https://", "   ", ""] {
            #expect(GatewayAddress.url(from: typed, path: "/x") == nil, "\(typed)")
        }
    }

    // MARK: - The route

    /// People paste the root, and people paste whatever their client's config
    /// or their own curl line ended at. Appending blindly makes `/v1/v1/…`.
    @Test("A suffix the reader already typed is not repeated")
    func typedSuffixesAreTrimmed() throws {
        for typed in [
            "https://gateway.example.com",
            "https://gateway.example.com/",
            "https://gateway.example.com/v1",
            "https://gateway.example.com/v1/",
        ] {
            let url = try #require(
                GatewayAddress.url(from: typed, path: "/v1/usage", trimming: ["/v1"]), "\(typed)"
            )
            #expect(url.absoluteString == "https://gateway.example.com/v1/usage", "\(typed)")
        }
    }

    /// Longest first, or `/v1/usage` is left as `/usage` by the rule meant to
    /// strip `/v1`.
    @Test("The longest matching suffix wins")
    func longestSuffixWins() throws {
        let url = try #require(GatewayAddress.url(
            from: "https://gateway.example.com/v1/usage",
            path: "/v1/usage",
            trimming: ["/v1", "/v1/usage"]
        ))
        #expect(url.absoluteString == "https://gateway.example.com/v1/usage")
    }

    /// A gateway behind a path prefix keeps it.
    @Test("A path prefix is kept and the route added after it")
    func pathPrefixIsKept() throws {
        let url = try #require(GatewayAddress.url(
            from: "https://example.com/gateway", path: "/v1/usage", trimming: ["/v1"]
        ))
        #expect(url.absoluteString == "https://example.com/gateway/v1/usage")
    }

    /// Only a suffix the caller named is dropped. A deployment that genuinely
    /// lives at `/v1` under a prefix keeps everything else.
    @Test("Only the named suffixes are trimmed")
    func unnamedSuffixesSurvive() throws {
        let url = try #require(GatewayAddress.url(
            from: "https://example.com/api/v2", path: "/status", trimming: ["/v1"]
        ))
        #expect(url.absoluteString == "https://example.com/api/v2/status")
    }
}
