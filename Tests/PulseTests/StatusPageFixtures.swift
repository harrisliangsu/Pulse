import Foundation
@testable import Pulse

/// The four pages the status tests were written against, by the names they
/// had when `StatusPage` was an enum of four.
extension StatusPage {
    static var openAI: StatusPage { .of(.codex)! }
    static var claude: StatusPage { .of(.claudeCode)! }
    static var deepSeek: StatusPage { .of(.deepSeek)! }
    static var cursor: StatusPage { .of(.cursor)! }
}

extension ServiceStatus {
    /// One incident.io group's components, nil when there are none — the
    /// shape the Codex tests read.
    static func incidentIOComponents(from data: Data, group: String) -> [Component]? {
        let components = incidentIOSummary(from: data)?.components.filter(ComponentRule.groups([group]).matches) ?? []
        return components.isEmpty ? nil : components
    }
}
