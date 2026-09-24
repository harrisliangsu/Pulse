import Foundation

/// One pass's primary-account reads, started together.
///
/// **One case per provider, and the only place a pass fetches one.**
/// The 1.4.3 sync kept two `async let qoderUsage` bindings: this fork and
/// upstream each added Qoder in a different part of `UsageStore.refresh`,
/// and git kept both. A second `case .qoder` in `read` does not compile.
/// A second `async let qoderUsage` pasted back into `UsageStore` is what
/// `Scripts/fork-compat-check.sh` rejects. Add a provider here. Do not add
/// an `async let` block beside the call.
struct UsageBatch: Sendable {
    var wanted: Set<Provider>
    var codex: CodexUsageService
    var codexSource: UsageSource
    var kiro: KiroUsageService
    var claudeCode: ClaudeCodeUsageService
    var claudeSource: UsageSource
    var antigravity: AntigravityUsageService
    var cursor: CursorUsageService
    var openCode: OpenCodeGoUsageService
    var kimi: KimiCodeUsageService
    var kimiSource: UsageSource
    var ollama: OllamaCloudUsageService
    var qoder: QoderUsageService
    var xiaomi: XiaomiMiMoUsageService
    var zai: ZaiUsageService
    var glm: ZaiUsageService
    var minimax: MiniMaxUsageService
    var minimaxCN: MiniMaxUsageService
    var copilot: CopilotUsageService
    var grok: GrokUsageService
    var grokBot: GrokBotUsageService
    var volcengine: VolcengineUsageService
    var volcengineSource: UsageSource
    var commandCode: CommandCodeUsageService
    var deepSeek: DeepSeekUsageService
    var devin: DevinUsageService
    var devinSource: UsageSource
    var sub2api: Sub2APIUsageService
    var newAPI: NewAPIUsageService
    var v2ex: V2EXUsageService

    private struct Reading: Sendable {
        var provider: Provider
        var usage: ProviderUsage
    }

    /// Side by side, same as the `async let` list this replaced: each child
    /// is on the main actor, so a fetch that touches the keychain or a
    /// browser store still runs where it did. Only `wanted` providers are
    /// started. Anything else keeps the reading it already has.
    func collect() async -> [Provider: ProviderUsage] {
        await withTaskGroup(of: Reading.self) { group in
            for provider in wanted {
                // A fresh binding per child. The loop variable itself is what
                // a concurrent capture warning is about.
                let provider = provider
                group.addTask { @MainActor in
                    Reading(provider: provider, usage: await self.read(provider))
                }
            }
            var readings: [Provider: ProviderUsage] = [:]
            for await reading in group {
                readings[reading.provider] = reading.usage
            }
            return readings
        }
    }

    private func read(_ provider: Provider) async -> ProviderUsage {
        switch provider {
        case .codex:
            await codex.fetch(source: codexSource)
        case .kiro:
            await kiro.fetch()
        case .claudeCode:
            await claudeCode.fetch(source: claudeSource)
        case .antigravity:
            await antigravity.fetch()
        case .cursor:
            await cursor.fetch()
        case .openCodeGo:
            await openCode.fetch()
        case .kimiCode:
            await kimi.fetch(source: kimiSource)
        case .ollamaCloud:
            await ollama.fetch()
        case .qoder:
            await qoder.fetch()
        case .xiaomiMiMo:
            await xiaomi.fetch()
        case .zai:
            await zai.fetch()
        case .glmCoding:
            await glm.fetch()
        case .minimax:
            await minimax.fetch()
        case .minimaxCN:
            await minimaxCN.fetch()
        case .copilot:
            await copilot.fetch()
        case .grok:
            await grok.fetch()
        case .grokBot:
            await grokBot.fetch()
        case .volcengine:
            await volcengine.fetch(source: volcengineSource)
        case .commandCode:
            await commandCode.fetch()
        case .deepSeek:
            await deepSeek.fetch()
        case .devin:
            await devin.fetch(source: devinSource)
        case .sub2api:
            await sub2api.fetch()
        case .newAPI:
            await newAPI.fetch()
        case .v2ex:
            await v2ex.fetch()
        }
    }
}
