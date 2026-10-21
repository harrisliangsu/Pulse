import Foundation
import Testing
@testable import Pulse

/// Answers the record route as Qoder would, told apart by the session's value
/// and the page asked for.
private final class QoderHistoryStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let scenario = cookie.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let page = items.first { $0.name == "page" }.flatMap { Int($0.value ?? "") } ?? 1
        let (status, body): (Int, String) = switch scenario {
        case "twoPages":
            (200, page == 1
                ? QoderCreditDaysTests.pageJSON([QoderCreditDaysTests.record(daysAgo: 0, used: 10, charged: 1)], page: 1, next: 2, last: 2)
                : QoderCreditDaysTests.pageJSON([QoderCreditDaysTests.record(daysAgo: 3, used: 5, charged: 0)], page: 2, next: nil, last: 2))
        case "secondFails":
            page == 1
                ? (200, QoderCreditDaysTests.pageJSON([QoderCreditDaysTests.record(daysAgo: 0, used: 10, charged: 1)], page: 1, next: 2, last: 2))
                : (500, "")
        case "endless":
            (200, QoderCreditDaysTests.pageJSON([QoderCreditDaysTests.record(daysAgo: 0, used: 1, charged: 1)], page: page, next: page + 1, last: 99))
        case "empty":
            (200, QoderCreditDaysTests.pageJSON([], page: 1, next: nil, last: 1))
        default:
            (401, "")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Qoder's last 31 days, from the account's own usage records (issue #88).
///
/// **The shape is second-hand**: written from the issue reporter's measured
/// replies on a mainland account (fields, spelling and paging), not captured
/// here. It pins what Pulse reads, not that the route still answers so.
@Suite("Qoder credit days")
struct QoderCreditDaysTests {
    static let now = Date()

    static func record(daysAgo: Int, used: Double, charged: Double) -> String {
        let at = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        let stamp = Int(at.timeIntervalSince1970 * 1_000)
        return """
        {"begin_at":\(stamp),"finish_at":\(stamp + 600_000),"time":\(stamp),"name":"",\
        "kind":"\(charged == 0 ? "Not Charged" : "Charged")","credits":\(charged),"original_credits":\(used)}
        """
    }

    static func pageJSON(_ records: [String], page: Int, next: Int?, last: Int) -> String {
        """
        {"data":[\(records.joined(separator: ","))],\
        "page_result":{"prev_page":\(page - 1),"current_page":\(page),"next_page":\(next.map(String.init) ?? "null"),\
        "last_page":\(last),"page_size":500}}
        """
    }

    private func fetch(_ scenario: String) async -> QoderCreditDays? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QoderHistoryStub.self]
        let client = QoderClient(session: URLSession(configuration: configuration))
        return await client.fetchCreditDays(cookie: "session=\(scenario)", site: .china, now: Self.now)
    }

    @Test("Pages are followed and both figures added up")
    func followsPages() async {
        let credits = await fetch("twoPages")
        #expect(credits?.days.count == QoderCreditDays.span)
        #expect(credits?.total(overLast: QoderCreditDays.span).used == 15)
        // A record Qoder does not bill counts to what was used, not to what was deducted.
        #expect(credits?.total(overLast: QoderCreditDays.span).charged == 1)
        // Today's own figure, and three days back on its own day.
        #expect(credits?.total(overLast: 1).used == 10)
        #expect(credits?.days.dropLast(3).last?.used == 5)
    }

    @Test("No records is a month of zeroes, not nothing")
    func emptyMonth() async {
        let credits = await fetch("empty")
        #expect(credits?.days.count == QoderCreditDays.span)
        #expect(credits?.total(overLast: QoderCreditDays.span).used == 0)
    }

    @Test("A failed page, a refused session or paging that never ends is no figure, not a part of one")
    func partialIsNothing() async {
        #expect(await fetch("secondFails") == nil)
        #expect(await fetch("signedOut") == nil)
        #expect(await fetch("endless") == nil)
    }

    @Test("A reply without its paging, or a record without its figures, is unreadable")
    func strictShape() throws {
        let stamp = Int(Self.now.timeIntervalSince1970 * 1_000)
        for body in [
            #"{"data":[]}"#,
            #"{"page_result":{"last_page":1}}"#,
            #"{"data":[{"credits":1,"original_credits":2}],"page_result":{"last_page":1}}"#,
            #"{"data":[{"begin_at":\#(stamp),"credits":1}],"page_result":{"last_page":1}}"#,
            #"{"data":[{"begin_at":\#(stamp),"original_credits":1}],"page_result":{"last_page":1}}"#,
            #"{"data":[{"begin_at":\#(stamp),"credits":-1,"original_credits":1}],"page_result":{"last_page":1}}"#,
        ] {
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(QoderClient.HistoryReply.self, from: Data(body.utf8))
            }
        }
        // camelCase is read as well, as on the credits route.
        let camel = #"{"data":[{"beginAt":\#(stamp),"credits":1,"originalCredits":2}],"pageResult":{"lastPage":1}}"#
        let reply = try JSONDecoder().decode(QoderClient.HistoryReply.self, from: Data(camel.utf8))
        #expect(reply.records.first?.originalCredits == 2)
    }

    @Test("The paging says when the window closed")
    func paging() {
        typealias Page = QoderClient.HistoryReply.PageResult
        #expect(Page(nextPage: nil, lastPage: 1).following(after: 1) == .last)
        #expect(Page(nextPage: 2, lastPage: 3).following(after: 1) == .next(2))
        #expect(Page(nextPage: 4, lastPage: 3).following(after: 3) == .last)
        #expect(Page(nextPage: 1, lastPage: 3).following(after: 2) == .unreadable)
        #expect(Page(nextPage: 5, lastPage: 3).following(after: 2) == .unreadable)
    }

    @Test("A record that began before the window is not counted, and each day is its own")
    func daysStartAtMidnight() {
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: Self.now))!
        let records = [
            QoderClient.HistoryReply.Record(beginAt: from.addingTimeInterval(-60), credits: 100, originalCredits: 100),
            QoderClient.HistoryReply.Record(beginAt: from, credits: 2, originalCredits: 3),
            QoderClient.HistoryReply.Record(beginAt: from.addingTimeInterval(3_600), credits: 1, originalCredits: 1),
        ]
        let credits = QoderCreditDays(records: records, from: from, now: Self.now, calendar: calendar)
        #expect(credits.days.count == 31)
        #expect(credits.days.first?.used == 4)
        #expect(credits.days.first?.charged == 3)
        #expect(credits.total(overLast: 31).used == 4)
        #expect(credits.total(overLast: 7).used == 0)
    }

    @Test("The request asks for the window, newest first, as the account page does")
    func requestShape() throws {
        let from = Date(timeIntervalSince1970: 1_789_000_000)
        let url = try #require(QoderSite.china.historiesURL(page: 2, from: from, to: from.addingTimeInterval(3_600)))
        #expect(url.host == "qoder.com.cn")
        #expect(url.path == "/api/v1/me/usages/big_model_credits/histories")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        #expect(items["page"] == "2")
        #expect(items["page_size"] == "500")
        #expect(items["start_time"] == "1789000000000")
        #expect(items["order_by"] == "begin_at")
        // No account id is asked for.
        #expect(items["userId"] == nil)
    }
}
