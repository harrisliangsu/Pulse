// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// Where a status page's data is read from, and in which shape.
///
/// **A feed is the company's, a page the provider's.** Two providers on one
/// company's page — Cursor and Grok Bot, Kimi Code and Moonshot, Codex and
/// the OpenAI Platform — share a feed, which the outage check reads once.
enum StatusFeed: Hashable, Sendable {
    /// Atlassian Statuspage: `/api/v2/summary.json`, and the bars from
    /// `/uptime_showcase` where the page draws them.
    case statuspage(URL)
    /// incident.io: the page's own `/proxy/<host>` feed and its
    /// `component_impacts`.
    case incidentIO(URL)
    /// Flashcat: the page itself, its data in the Next.js payload.
    case flashcat(URL)
    /// Better Stack: `/index.json`, the state and the days in one request.
    case betterStack(URL)
    /// Instatus: `/v2/components.json`. The state only; the bars are drawn
    /// in the page and never published.
    case instatus(URL)
    /// Upptime: the repository's `history/summary.json`. The state only: it
    /// lists the days with downtime, and no start before which a day is
    /// unknown rather than clear.
    case upptime(URL)
    /// Gatus: `/api/v1/endpoints/statuses`, the last checks. The state only.
    case gatus(URL)
    /// UptimeRobot: a public page's `getMonitorList`, ninety daily ratios.
    case uptimeRobot(URL)
    /// OpenCode's own `/api/status`: the state, and the page's bars — seven
    /// days in three-hour slots.
    case openCode(URL)
    /// DeepInfra's own `/api/v1/status`, its services (not its models).
    case deepInfra(URL)
    /// IBM Bob's own `/api/v1/status`.
    case ibmBob(URL)
    /// Google Cloud's `incidents.json`: one product's incidents, drawn as
    /// days the way incident.io's impacts are.
    case googleCloud(URL, product: String, name: String)
}

/// Which components on a page a provider's pane shows, or a notification is
/// about. **By id where the page has stable ids**, because names change and
/// ids don't; by group where the rows under it come and go (a model a row);
/// by name only where the page gives nothing better.
indirect enum ComponentRule: Hashable, Sendable {
    case all
    case ids(Set<String>)
    /// The group a component is drawn under: Statuspage's group id,
    /// incident.io's, Better Stack's or Instatus's group name, Flashcat's
    /// section id.
    case groups(Set<String>)
    /// Any of these in the name.
    case nameContains([String])
    case except(ComponentRule)

    func matches(_ component: ServiceStatus.Component) -> Bool {
        switch self {
        case .all: true
        case .ids(let ids): ids.contains(component.id)
        case .groups(let groups): component.group.map(groups.contains) ?? false
        case .nameContains(let parts): parts.contains { component.name.contains($0) }
        case .except(let rule): !rule.matches(component)
        }
    }
}

/// A provider's own status page: where it is, whose it is, and what on it
/// belongs to the provider.
///
/// **The page's word, not Pulse's.** Every page here was found on the
/// provider's own site or redirected to from its `status.` address, and read
/// with the request Pulse makes (2026-10-15). A provider with no page, or one
/// Pulse can't read without a browser — xAI's and Mistral's sit behind a bot
/// check — has none here rather than a stand-in. Docs/providers/README.md,
/// "Service status".
struct StatusPage: Hashable, Sendable, Identifiable {
    /// The provider whose pane shows it, and whose name a notification bears.
    let provider: Provider
    /// The page a person opens.
    let address: URL
    /// Who is speaking on the page, for the footnote.
    let company: String
    let feed: StatusFeed
    /// What on the page belongs to the provider: the rows the pane draws, and
    /// the only ones a notification can be about.
    var shows: ComponentRule = .all
    /// Of those, what an outage is worth a notification for: what the
    /// provider's account runs on — the API a key is spent through, the agent
    /// a plan pays for — not the marketing site or the docs.
    var notifies: ComponentRule = .all
    /// How many days the page draws, ending today, where Pulse lays the days
    /// out itself (incident.io, Flashcat, Google Cloud). Other feeds give
    /// their own.
    var dayCount = 90

    var id: String { provider.rawValue }
    var host: String { address.host() ?? "" }

    func notifiesAbout(_ component: ServiceStatus.Component) -> Bool {
        shows.matches(component) && notifies.matches(component)
    }
}

extension StatusPage {
    /// The provider's page, nil where it has none Pulse reads. MiniMax's
    /// depends on which site the account is on.
    static func of(_ provider: Provider, minimaxSite: MiniMaxSite = .international) -> StatusPage? {
        switch provider {
        // MARK: Atlassian Statuspage
        case .claudeCode:
            // Claude Code, and the API it runs on.
            statuspage(provider, "https://status.claude.com", "Anthropic",
                       notifies: .ids(["yyzkbfz2thpt", "k8w3r06qmzrp"]))
        case .cursor:
            // The IDE, the CLI and Cloud Agents — what the account's usage is
            // spent through — not cursor.com, Automations, Review Agents or
            // the unexplained "Origin". Grok Bot is a provider of its own.
            statuspage(provider, "https://status.cursor.com", "Cursor",
                       shows: .except(.ids(["sm5wkcnqkvr9"])),
                       notifies: .ids(["rflc60xp5jp2", "vsny1qv7v86c", "mwv1g9sc7kdh"]))
        case .grokBot:
            statuspage(provider, "https://status.cursor.com", "Cursor", shows: .ids(["sm5wkcnqkvr9"]))
        case .copilot:
            // GitHub's page; Copilot and the model providers behind it.
            statuspage(provider, "https://www.githubstatus.com", "GitHub",
                       shows: .ids(["pjmpxvq2cmr2", "cnnb39dkkk82"]))
        case .devin:
            // Not the Enterprise and Federal deployments' copies.
            statuspage(provider, "https://www.devinstatus.com", "Cognition",
                       shows: .except(.groups(["92j5h0ttqxfb", "9ydbk2b55pk1"])),
                       notifies: .ids(["q72cy1kjpk4r", "d87cp5jknh1c"]))
        case .windsurf:
            // Cascade and Tab; not the Netlify rows the page mirrors.
            statuspage(provider, "https://status.windsurf.com", "Windsurf",
                       shows: .ids(["r5wf1ykd7y1m", "8q19cygxvshj"]))
        case .augment:
            statuspage(provider, "https://status.augmentcode.com", "Augment Code",
                       notifies: .ids(["1k3gvg4j889s"]))
        case .factory:
            // Not the Models group: other companies' models, mirrored.
            statuspage(provider, "https://status.factory.ai", "Factory",
                       shows: .except(.groups(["c9sjq8nsz2kq"])),
                       notifies: .ids(["kfqc4mfdkrqx", "jfcmwr3grbyc", "z1frly8fm1l5"]))
        case .kiloCode:
            // Not the Service Provider group: Cloudflare, Fly.io, WorkOS.
            statuspage(provider, "https://status.kilo.ai", "Kilo",
                       shows: .except(.groups(["frgc645htq00"])),
                       notifies: .ids(["kdk5t7ljzmm1", "rkvq7kvz2zlh"]))
        case .minimax:
            switch minimaxSite {
            case .international:
                statuspage(provider, "https://status.minimax.io", "MiniMax", notifies: .ids(["pr0d8qr59svt"]))
            case .china:
                statuspage(provider, "https://status.minimaxi.com", "MiniMax", notifies: .ids(["vwp8mgy34fck"]))
            }
        case .kimiCode:
            // By group: a row per model, and the models change.
            statuspage(provider, "https://status.moonshot.cn", "Moonshot AI", shows: .groups(["cyrtlddz0q8c"]))
        case .moonshot:
            // The open platform's group: the API and its console.
            statuspage(provider, "https://status.moonshot.cn", "Moonshot AI",
                       shows: .groups(["87jpctq5cp71"]),
                       notifies: .ids(["8psr5dfdld0s", "pjrph68g94yr"]))
        case .warp:
            statuspage(provider, "https://status.warp.dev", "Warp",
                       notifies: .ids(["z7hlxwbqx7ry", "z90zfbttkx9f", "7z5yq9wznb4f"]))
        case .manus:
            statuspage(provider, "https://status.manus.im", "Manus")
        case .venice:
            statuspage(provider, "https://veniceai-status.com", "Venice", notifies: .ids(["6knqw5vybqzk"]))
        case .zoomMate:
            // One row of Zoom's 339. Zoom draws no bars for any of them.
            statuspage(provider, "https://www.zoomstatus.com", "Zoom", shows: .ids(["n1llzwc1cxtr"]))
        case .replicate:
            // Replicate's status addresses lead to Cloudflare's page, which
            // lists it as a service and draws no bars.
            statuspage(provider, "https://www.cloudflarestatus.com", "Cloudflare", shows: .ids(["fvgfcmy66tdr"]))

        // MARK: incident.io
        case .codex:
            incidentIO(provider, "https://status.openai.com", "OpenAI", shows: .groups(["Codex"]), dayCount: 91)
        case .openAIPlatform:
            incidentIO(provider, "https://status.openai.com", "OpenAI", shows: .groups(["APIs"]), dayCount: 91)
        case .jetBrainsAI:
            // Not the AI Providers group: other companies' models, mirrored.
            incidentIO(provider, "https://status.jetbrains.cloud", "JetBrains",
                       shows: .except(.groups(["AI Providers"])),
                       notifies: .ids(["01KX3EN535A0SKSZK3S84949V1"]))
        case .amp:
            // The agent and the site; the rest is mirrored from suppliers.
            incidentIO(provider, "https://ampcodestatus.com", "Amp",
                       shows: .ids(["01KBQ3ZK9NMBWKR7DY9H7NQ17D", "01M0WN9KPF89TDEHSPQ918XHTH"]))
        case .aixy:
            incidentIO(provider, "https://status.aixy-gateway.com", "AIXY",
                       notifies: .ids(["01M08789J59XQG5AR373SVQZ6Z"]))
        case .elevenLabs:
            incidentIO(provider, "https://status.elevenlabs.io", "ElevenLabs", shows: .groups(["ElevenAPI"]))
        case .notionAI:
            incidentIO(provider, "https://www.notion-status.com", "Notion", shows: .groups(["Notion AI"]))
        case .perplexity:
            incidentIO(provider, "https://status.perplexity.com", "Perplexity",
                       notifies: .ids(["01M2R6E5FPASTEW3A3V8TSYHJ0"]))
        case .poe:
            incidentIO(provider, "https://status.poe.com", "Poe")
        case .v0:
            incidentIO(provider, "https://v0-status.com", "Vercel",
                       notifies: .ids(["01KHYYTCKK0NS8FN857PCJB63W", "01J5EED92VTMVYNWYKYS9B1G1F"]))

        // MARK: Flashcat
        case .deepSeek:
            // Pulse reads the API account; its rows are named after the model
            // ("DeepSeek V4 Pro API服务"), and the chat site is not the API.
            page(provider, "https://status.deepseek.com", "DeepSeek",
                 feed: .flashcat(URL(string: "https://status.deepseek.com/")!),
                 notifies: .nameContains(["API"]))

        // MARK: Better Stack
        case .huggingFace:
            betterStack(provider, "https://status.huggingface.co", "Hugging Face", notifies: .ids(["306621", "84641"]))
        case .chutes:
            betterStack(provider, "https://status.chutes.ai", "Chutes", notifies: .ids(["8599285"]))
        case .synthetic:
            betterStack(provider, "https://status.synthetic.new", "Synthetic",
                        notifies: .groups(["Synthetic - API (Synthetic hosted Models)"]))
        case .devPass:
            betterStack(provider, "https://status.llmgateway.io", "LLM Gateway", notifies: .ids(["8768001"]))
        case .raycastAI:
            betterStack(provider, "https://status.raycast.com", "Raycast", notifies: .ids(["5341215"]))
        case .typeSafe:
            betterStack(provider, "https://status.typesafe.ai", "TypeSafe", notifies: .ids(["8735312"]))

        // MARK: Instatus
        case .zed:
            // Not Delta, the company's other product.
            instatus(provider, "https://status.zed.dev", "Zed",
                     shows: .except(.groups(["Delta"])),
                     notifies: .ids(["cmaw974wo0001xh7v9vfihlul", "cm75bq8t9000rsdcb9bfls8wt"]))
        case .gitKraken:
            instatus(provider, "https://cloud.gitkrakenstatus.com", "GitKraken",
                     notifies: .ids(["clvkz1ojq2917bgo9peyj3bha", "clvkz1ok12924bgo956mkaa0r"]))
        case .atlasCloud:
            instatus(provider, "https://atlascloud.instatus.com", "Atlas Cloud")

        // MARK: Monitors and companies' own
        case .commandCode:
            page(provider, "https://status.commandcode.ai", "Command Code",
                 feed: .upptime(URL(string: "https://raw.githubusercontent.com/CommandCodeAI/commandcode-status/master/history/summary.json")!))
        case .clinePass:
            page(provider, "https://status.cline.bot", "Cline",
                 feed: .gatus(URL(string: "https://status.cline.bot/api/v1/endpoints/statuses")!))
        case .hyper:
            // Charm's page; Hyper's own monitor of its five.
            page(provider, "https://status.charm.sh", "Charm",
                 feed: .uptimeRobot(URL(string: "https://status.charm.sh/api/getMonitorList/JrppyTBzE3?page=1")!),
                 shows: .ids(["803945156"]))
        case .openCodeGo:
            page(provider, "https://status.opencode.ai", "OpenCode",
                 feed: .openCode(URL(string: "https://status.opencode.ai/api/status")!),
                 notifies: .ids(["go"]))
        case .deepInfra:
            page(provider, "https://status.deepinfra.com", "DeepInfra",
                 feed: .deepInfra(URL(string: "https://status.deepinfra.com/api/v1/status")!),
                 notifies: .ids(["api"]))
        case .ibmBob:
            page(provider, "https://status.bob.ibm.com", "IBM",
                 feed: .ibmBob(URL(string: "https://status.bob.ibm.com/api/v1/status")!),
                 notifies: .ids(["Chat/Code Completion", "Login/SSO"]))
        case .gemini:
            // Pulse reads Gemini Code Assist's quota; Google's dashboard lists
            // it as a product. AI Studio's own status page has no public feed.
            page(provider, "https://status.cloud.google.com", "Google Cloud",
                 feed: .googleCloud(URL(string: "https://status.cloud.google.com/incidents.json")!,
                                    product: "deUeOEPYanfJ9w8cpyBJ", name: "Gemini Code Assist"))

        default: nil
        }
    }

    /// Every page Pulse knows, both of MiniMax's included — for the tests.
    static var catalogue: [StatusPage] {
        Provider.builtIn.compactMap { of($0) } + [of(.minimax, minimaxSite: .china)].compactMap { $0 }
    }

    private static func page(
        _ provider: Provider, _ address: String, _ company: String, feed: StatusFeed,
        shows: ComponentRule = .all, notifies: ComponentRule = .all, dayCount: Int = 90
    ) -> StatusPage {
        StatusPage(provider: provider, address: URL(string: address)!, company: company, feed: feed,
                   shows: shows, notifies: notifies, dayCount: dayCount)
    }

    private static func statuspage(
        _ provider: Provider, _ root: String, _ company: String,
        shows: ComponentRule = .all, notifies: ComponentRule = .all
    ) -> StatusPage {
        page(provider, root, company, feed: .statuspage(URL(string: root)!), shows: shows, notifies: notifies)
    }

    private static func incidentIO(
        _ provider: Provider, _ root: String, _ company: String,
        shows: ComponentRule = .all, notifies: ComponentRule = .all, dayCount: Int = 90
    ) -> StatusPage {
        let url = URL(string: root)!
        return page(provider, root, company, feed: .incidentIO(url.appending(path: "proxy/\(url.host() ?? "")")),
                    shows: shows, notifies: notifies, dayCount: dayCount)
    }

    private static func betterStack(
        _ provider: Provider, _ root: String, _ company: String, notifies: ComponentRule = .all
    ) -> StatusPage {
        page(provider, root, company, feed: .betterStack(URL(string: root)!.appending(path: "index.json")), notifies: notifies)
    }

    private static func instatus(
        _ provider: Provider, _ root: String, _ company: String,
        shows: ComponentRule = .all, notifies: ComponentRule = .all
    ) -> StatusPage {
        page(provider, root, company, feed: .instatus(URL(string: root)!.appending(path: "v2/components.json")),
             shows: shows, notifies: notifies)
    }
}

extension AppSettings {
    /// The page this provider's pane shows and the outage check reads, on the
    /// site its account is on.
    func statusPage(for provider: Provider) -> StatusPage? {
        StatusPage.of(provider, minimaxSite: minimaxSite)
    }
}
