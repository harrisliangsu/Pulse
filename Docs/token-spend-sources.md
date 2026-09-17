# Token spend sources

Owns: the complete list of agent stores the Token spend pane can read — default macOS location, store format, the counters it really reports, and how well each one is evidenced. The pane itself and what may be said about its figures: [token-spend.md](token-spend.md).

Pulse's catalog recognizes **54 agent sources**: the seven clients it read on a real machine before this change (`claudeCode`, `codex`, `openCode`, `kiloCLI`, `grok`, `kimiCLI`, `devinCLI`) and **47** added from second-hand format specifications of a compatibility target (Tokscale 4.17.0). Some sources require exports or do not report usable token counters; the table below distinguishes them. No upstream code, test or fixture is vendored; each added reader was written independently from file locations, field meanings, units and event identities, with original synthetic test data. The new readers have not been verified against live client stores.

The canonical id is `SpendAgent.sourceID` (the string the reader families dispatch on); the seven legacy cases keep their Swift `rawValue` identities. The cache format is versioned separately and older formats are reread. `hasCapturedValidation` is true only for those seven existing readers.

## Evidence levels

- **machine** — the reader existed in Pulse and was run against a real store with real work in it.
- **spec** — written from a second-hand format spec and checked with synthetic stores. The shape is pinned against change; it is **not** proof the shape is right.
- **export** — as *spec*, and additionally depends on a prior export, sync or capture performed by another tool. Without that prerequisite there is nothing to read.

## Counter status

- **real** — the store reports measured input/output/cache counters; the reader uses only them.
- **real, session total** — real counters that exist only as a session/report aggregate; timing is coarse.
- **partial source** — some shape or row cannot prove the report is complete (an ambiguous cache or reasoning relation, or real usage with no locatable time or model), so records from it are marked `isPartial`.
- **cost only** — the store reports money or request counts and no measured tokens. Pulse reports no token figure for it.
- **estimated only** — the store leaves only character-based estimates. Pulse does not report them as usage.

`AgentUsageRecord.isPartial` says a source could not establish a complete count. It never adds or guesses a remainder and changes no price; it propagates to `UsageLedger.hasPartialCounts`, `SpendSummary.hasPartialCounts` and `ModelSpendSummary.hasPartialCounts`, and the UI says "Counts may be incomplete." `unclassifiedTokens` instead preserves a reported quantity without assigning a kind; `isAggregate` marks coarse session/report timing. These flags can coexist.

The six new reader families expose two entry points: `inputs(client:home:environment:)` declares input candidates, and `records(client:roots:)` decodes them into `AgentUsageRecord` increments. Existing inputs form the cache fingerprint; roots are rediscovered after reading. Every counter is priced through the shared function in [token-spend.md](token-spend.md#what-the-readers-agree-on). Compression failures (a missing decoder, corrupt frame or size limit) are reported through `notes`; a read with notes is shown but **not persisted** to disk.

## Group A — session logs (`SessionLogReaders`)

Pi-shaped JSONL: a session header, assistant `message` records, and a `usage` object with four independent buckets. Cross-session dedup by response/message identity so a fork copy collapses.

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `pi` | `~/.pi/agent/sessions/**/*.jsonl` | real | spec |
| `omp` | `~/.omp/agent/sessions/**/*.jsonl` | real | spec |
| `senpi` | `~/.senpi/agent/sessions`, plus `.omo/senpi-task/children` for each recorded `cwd` | real | spec |
| `kimchi` | `~/.config/kimchi/harness/sessions` | real | spec |
| `prime-agent` | `~/.prime/agent/sessions` + `session-artifacts`, redirected by a `settings.json` `sessionDir` | real, after parent/child reconciliation | spec |
| `gemini` | `~/.gemini/tmp` (legacy `session-*.json`, `tmp/<id>/chats/*.json`, headless `*.jsonl`) | real; the session shape folds tool tokens into fresh input, the headless shape ignores them; an unsettled cache relation marks records partial | spec |
| `qwen` | `~/.qwen/projects/<project>/chats/*.jsonl` | real; `cache_read` sits **inside** `promptTokenCount` per the documented `usageMetadata`, and a reported total proves or refutes the overlap; an unsettled line is partial | spec |
| `amp` | `~/.local/share/amp/threads/T-*.json` | real | spec |
| `droid` | `~/.factory/sessions/*.settings.json` + sibling `*.jsonl` | real session total; with no total and a positive cache, output is priced, input is unclassified and the record is partial | spec |
| `openclaw` | `~/.openclaw/agents` (SQLite `openclaw-agent.sqlite`, legacy `sessions/*.jsonl`) plus legacy `~/.clawdbot`, `~/.moltbot`, `~/.moldbot` | real; mirrored Codex rollouts and `.zst` archives are not read, and an incomplete read is partial | spec |

`PI_CODING_AGENT_DIR` is read by both Pi and omp, so neither reader honours it — watching it twice would count one tree twice. `SENPI_CODING_AGENT_DIR`/`_SESSION_DIR`, `KIMCHI_CODING_AGENT_DIR`, the `PRIME_AGENT_*` keys and `GEMINI_CLI_HOME` are honoured where the spec says the client does. Qwen's cache relation follows Google's documented `usageMetadata`: `promptTokenCount` includes cached content and a reported `totalTokenCount` is the authority that settles it, so a relation the store does not state is carried as unclassified rather than guessed. In the Pi-shaped family and Amp, real usage with no usable model or locatable time makes the whole read partial rather than being dropped silently.

## Group B — editors, buddies and standalone logs (`EditorLogReaders`)

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `roocode` | `~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/tasks/`, `~/.config/Code/…`, Insiders/VSCodium and `.vscode-server` variants | real | spec |
| `kilocode` | the same editor roots for `kilocode.kilo-code` | real | spec |
| `cline` | the Cline task logs plus the Cline CLI roots (`CLINE_SESSION_DATA_DIR`, `CLINE_DATA_DIR/sessions`, `~/.cline/data/sessions`) | real | spec |
| `codebuddy` | `~/.codebuddy/projects/**/*.jsonl`; IDE extension logs only when no transcript exists | real; transcript + excluded fallback is partial | spec |
| `workbuddy` | `~/.workbuddy/projects`, `~/.workbuddy-ai/projects`; `workbuddy.db` only as a fallback | real; the SQLite fallback reports an **unclassified** aggregate, not fresh input | spec |
| `cherrystudio` | `~/Library/Application Support/CherryStudio/Data/Agents/.claude/projects/` (V2), `~/Library/Application Support/CherryStudio/.claude/projects/` (V1) | real | spec |
| `commandcode` | `~/.commandcode/projects/<slug>/<session>.jsonl` | modern real; a legacy line with no `usage` block contributes **nothing** | spec |
| `opencodereview` | `~/.opencodereview/sessions/<encoded-repo>/<session-id>.jsonl` | the store's own total settles the cache relation; no total with a positive cache is skipped, and remaining records are partial | spec |
| `zcode` | `~/.zcode/projects/**/*.jsonl`, `~/.zcode/cli/db/db.sqlite` | modern real; a reported total subtracts the cache overlap, a bare total is unclassified, a legacy line with no usage contributes nothing | spec |

The VS Code task logs are `ui_messages.json` (`say == "api_req_started"`), each carrying the four counts in an inner JSON string. Cherry Studio appends the same API call several times with one `requestId`; the reader merges those by field-wise maximum so a streamed snapshot is not counted as new usage. Command Code is a tree, but **every reply with reported usage counts**, including abandoned branches: `/rewind` changes context, not already consumed tokens. Its session/message id folds replays, while its own ancestry resolves an omitted model so a sibling branch's model change cannot reprice it. Tencent's **JSONL transcript is the only reconcilable channel**: when it is present the extension log and the aggregate database are not returned, because they share no identity with its message ids and adding them would double count; when that excluded fallback held records, the transcript records are marked `isPartial`. With no transcript, the fallback stands alone — and a mirrored log line may then be counted twice, which is preferred to folding two real same-second requests into one.

## Group C — databases and event logs (`DatabaseLogReaders`)

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `hermes` | `$HERMES_HOME` else `~/.hermes`, `state.db` and `profiles/*/state.db` | real session aggregate; with a cache, input is unclassified and the cache is not added; a positive cache or reasoning is partial | spec |
| `goose` | `~/Library/Application Support/goose/sessions/sessions.db` (and the `Block/goose` legacy roots) | input/output real; the `total − input − output` remainder is **unclassified**, not reasoning; no cache columns; aggregate | spec |
| `zed` | `~/Library/Application Support/Zed/threads/threads.db` | real aggregate; no reasoning field; `zstd` threads decoded through the shared system-library decoder | spec |
| `kiro` | `~/.kiro/sessions/cli/*.json` + sibling `*.jsonl` | only explicit `input_token_count`/`output_token_count` are real; estimate-only variants are not read | spec |
| `crush` | `projects.json` registry (XDG/`CRUSH_GLOBAL_DATA`) + each projected `crush.db` | **cost only** — no token records, by design | spec |
| `unsloth` | `$UNSLOTH_STUDIO_HOME` else `~/.unsloth/studio/studio.db` | real | spec |
| `antigravity-cli` | `$GEMINI_CLI_HOME` else `~/.gemini`, `antigravity-cli/conversations/*.db` | real; `#1` is not counted and `#9.#10` is never decoded into a time; every record is partial | spec |
| `antigravity-ide` | the same root, `antigravity/conversations/*.db` and `antigravity-ide/conversations/*.db` | as `antigravity-cli` — same store shape, same reader, same partial rule | spec |
| `micode` | `<xdg_data>/mimocode/mimocode*.db`, plus the Orca hook sandbox copy under `~/Library/Application Support/orca/` | real | spec |
| `devin-desktop` | `~/Library/Application Support/Devin/User/acp-events/*.ndjson`, `~/.config/devin/User/acp-events` | NDJSON counters; the native DB resolves identity and excludes counted-session mirrors, but does not establish Desktop presence | spec |

Hermes carries the reported `input_tokens` as **unclassified** once a cache column is non-zero, and does not add the cache or the `reasoning_tokens` column — the schema does not establish either relation, and summing would double count a subset. Antigravity CLI counts only the fields with an observed meaning (`#2`, `#5`, `#9`, `#10`, with `#9 + #10` the output contract counted once); the near-constant `#1` is read by nothing, and the unknown `#9.#10` bytes are never turned into an event time. A turn with no proven timestamp falls back to the conversation's created-at and is marked aggregate.

## Group D — per-product stores (`StructuredLogReaders`)

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `mux` | `~/.mux/sessions/<workspaceId>/session-usage.json` | real session total per model; ambiguous reasoning is omitted and the record is partial | spec |
| `codebuff` | `~/.config/manicode{,-dev,-staging}/projects/<project>/chats/<chatId>/chat-messages.json` | real | spec |
| `freebuff` | the same Codebuff trees, `base2-free*` chats | **estimated only** — no persisted counters | spec |
| `jcode` | `~/.jcode/sessions/session_*.json` + `session_*.journal.jsonl` | real; an ambiguous cache makes input unclassified and the record partial, as does omitted reasoning | spec |
| `augment` | `~/.augment/sessions/<sessionId>.json` | real | spec |
| `gjc` | `~/.gjc/agent/sessions` (plus `GJC_CODING_AGENT_DIR`/`GJC_CONFIG_DIR`/`PI_CONFIG_DIR`/`XDG_DATA_HOME` spellings) | real | spec |
| `junie` | `~/.junie/sessions/<session-id>/events.jsonl` | real; ambiguous reasoning is omitted and the record is partial | spec |
| `dsh` | `~/.dsh/sessions` (`session.jsonl` or `session.jsonl.zstd`) | real; `outputTokens` already includes reasoning, kept once | spec |
| `fx` | `~/.fx/sessions/<sessionId>/usage-v2.json` | real session total per model; ambiguous reasoning is omitted and the record is partial | spec |
| `lmstudio` | `~/.lmstudio/server-logs/**/*.log` | real; completion already includes reasoning, kept once | spec |
| `reasonix` | `~/.reasonix/stats/YYYY-MM-DD.jsonl` | real; completion already includes reasoning, kept once | spec |

`CODEBUFF_DATA_DIR`, `FREEBUFF_DATA_DIR`, `JCODE_HOME`, `DSH_HOME`, `LM_STUDIO_HOME` and `REASONIX_HOME`/`REASONIX_STATE_HOME` replace the defaults. DSH's compression is decided by the zstd frame magic, not the extension, with raw and decoded ceilings so a torn trailing frame or a high-ratio file cannot allocate without bound. The two reasoning conventions are kept apart: where the format states reasoning is inside output (`dsh`, `lmstudio`, `reasonix`) it is counted once and the record is complete on that axis; where the format states nothing (`mux`, `fx`, `jcode`, `junie`) the ambiguous figure is omitted and the record is marked partial rather than guessed either way. Jcode also never infers a cache convention from magnitude: an unmarked positive cache leaves the input unclassified and the cache uncounted.

## Group E — exports, caches and captures (`CapturedUsageReaders`)

None of these six products writes an unauthenticated native usage log Pulse can read on its own. Each reader reads a cache/export/capture that some other tool produced, **plus** Pulse's own drop folder `~/Library/Application Support/Pulse/UsageImports/<client>`. Pulse does not log in, capture a cookie, call a language server or sync anything.

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `cursor` | `<config>/cursor-cache/` (`usage*.json`, legacy `usage*.csv`) | real; JSON supersedes CSV; no per-event id, so equal rows are kept and overlapping exports are reconciled by multiset and marked partial | export |
| `antigravity` | `<config>/antigravity-cache/sessions/*.jsonl` | real; ambiguous reasoning is omitted and the record is partial | export |
| `trae` | `<config>/trae-cache/sessions/*.json` | real; no per-row id, so equal rows are kept and overlapping pages are reconciled by multiset and marked partial | export |
| `warp` | `<config>/warp-cache/usage*.json` | **cost/requests only — no tokens in the format** | export |
| `hindsight` | `$HINDSIGHT_HOME/usage/` else `~/.hindsight/usage/*.jsonl` | real; output already includes reasoning, kept once | export |
| `mcode` | `<config>/headless/mcode/*.jsonl` | real; a message is merged only by its own id, never by equal counts | export |

`<config>` is `$TOKSCALE_CONFIG_DIR` when set, else `~/.config/tokscale`. Warp is the sharpest case: its cache carries `requestsUsed` and `spendCents` and no token fields at all, so the tally is zero and must stay zero — a UI that shows tokens or a zero that reads as a token number would be inventing one. `antigravity` here is the IDE cache; it is a different source from `antigravity-cli` in Group C, whose conversations are read directly.

**Cursor and Trae carry no declared account and no per-event id.** Two equal rows **inside one file/page** are left as two records — they can be two real requests — while the same row across **files of one scope** is reconciled by content multiset (`{A}` and `{A, B}` give `A` and `B`), and an unconfirmed increment in the shared region is marked `isPartial`. A native `usage.<account>` name declares a real account; a file that declares none shares one unknown import scope, and an event with no `conversationId`/`Cloud Agent ID` counts its tokens but creates **no** session row rather than a synthetic account or per-day id. A JSON file is read when its root holds `usageEventsDisplay`; a CSV when its header names the date, model and four counters. Precisely because a dropped file may cover a narrower range than Pulse assumes, the coverage of the JSON and CSV shapes is a **known subset**, not a proved whole.

## Group F — the seven existing readers, and Copilot

`copilot` merges three local stores into one client, in priority order OTEL → Desktop SQLite → VS Code `chatSessions`; each later lane is filtered against the earlier ones so one call is counted once.

| Client | Default macOS location | Counter status | Evidence |
|---|---|---|---|
| `copilot` | `~/.copilot/otel/*.jsonl`; `~/.copilot/data.db` + `session-state/<id>/events.jsonl`; `~/Library/Application Support/Code/User/workspaceStorage/*/chatSessions/*.jsonl` | real; an OTEL record with no trace/response id, a desktop record with ambiguous reasoning, and OTEL covering only part of a desktop lifetime are all partial | spec |

The three lanes do not share a dedup key across sources. An OTEL usage line with neither a trace id nor a response id is counted as its own event and marked `isPartial` — never folded onto another by a shared instant. The desktop SQLite row is a lifetime total and its sidecar writes cumulative running snapshots that are differenced per model; the database row remains the authority, and a session already seen in OTEL is dropped whole. When that desktop lifetime is larger than what OTEL recorded, the OTEL records are marked `isPartial`: the difference is stated, not subtracted, because an OTEL span and a desktop lifetime are not equal scopes. Desktop reasoning is ambiguous (the schema does not declare it a subset of output), so it is omitted and the record is partial. A VS Code request with no timestamp is **skipped**, not dated at the epoch.

The seven existing clients retain these currently implemented locations:

| Canonical client | Swift case | Current location |
|---|---|---|
| `claude` | `claudeCode` | `~/.claude/projects` |
| `codex` | `codex` | `~/.codex/sessions` |
| `opencode` | `openCode` | `~/.local/share/opencode/opencode.db` |
| `kilo` | `kiloCLI` | `~/.local/share/kilo/kilo.db` |
| `grok` | `grok` | `~/.grok/sessions` |
| `kimi` | `kimiCLI` | `~/.kimi/sessions` |
| `devin-cli` | `devinCLI` | `~/.local/share/devin/cli/sessions.db` |

The compatibility reference also describes additional locations and formats **not added to those seven readers in this change**:

| Client | Additional sources (spec) |
|---|---|
| `claudeCode` | `$CLAUDE_CONFIG_DIR`; `<root>/transcripts`; cc-mirror variants; sidechain `subagents/**/agent-*.jsonl` (skip a `journal.jsonl`); tool-result usage |
| `codex` | `$CODEX_HOME`; `archived_sessions/**/*.jsonl`; headless captures; `reasoning_output_tokens` subtraction; `session_meta.originator == "openclaw"` retags the rollout to `openclaw` |
| `openCode` | channel DBs `opencode-<channel>.db`; v2 `session_message` schema; legacy `storage/message` JSON; cross-DB dedup by embedded message id |
| `kiloCLI` | Kilo's snake_case session id; a timestamp-less message needs an evidenced time, not the database's modification date |
| `grok` | `logs/unified.jsonl`; sibling `signals.json` reconciliation; `GROK_HOME` |
| `kimiCLI` | Kimi Code (`KIMI_CODE_HOME` or `~/.kimi-code`); Kimi Work desktop protocol; `config.json` model; `output` already includes reasoning |
| `devinCLI` | Windows `%APPDATA%` root; `metadata.num_tokens` attributed to output when `metrics` is absent |

Codex's `input_tokens` includes cached input, so fresh input subtracts that overlap. Its `output_tokens` already includes reasoning; Pulse's output bucket keeps that full output count once.

## Compression is a local library, not an OS guarantee

DSH transcripts and Zed's `zstd` threads need a zstd decoder. Pulse does **not** vendor one: it resolves the system library by explicit path, in order — `/usr/lib/libzstd.1.dylib`, `/opt/homebrew/lib/libzstd.1.dylib`, `/usr/local/lib/libzstd.1.dylib` — and never by bare name. A Homebrew `libzstd` on this machine works; another machine may have none. When no library loads, a frame is corrupt, or a raw/decoded bound is exceeded, the reader reports a `note` rather than treating the transcript as empty, and that read is not written to the disk cache, so a later build with a decoder can still recover it. OpenClaw's `.zst` archives remain unread even when a decoder exists, because its own reader does not decode them.

## Cross-source routing and dedup

- **OpenClaw** deduplicates its native stores by recorded event identity. Retagging Codex app-server rollouts and reconciling those mirrors are not implemented; combined mirrored source sets need further validation.
- **OpenCode** retains its existing database reader. Multi-channel and legacy-message reconciliation remain additional format work, rather than a property of this catalog expansion.
- **Copilot OTEL → Desktop → VS Code**, filtered by session id and then by dedup key or `(session_id, timestamp)`.
- **Kiro** reads explicit CLI counters. The estimate-based IDE and database snapshot variants are not parsed.
- **Devin Desktop vs Devin**: the Desktop NDJSON resolves its session/model/workspace from the database by an unambiguous title. In the combined catalogue, a session with usable dated message counters in the native Devin database belongs to that database; its Desktop capture is a mirror and is excluded before pricing. The counted-session test uses `DevinCLIStore`'s actual message parser, not the existence of a metadata row. A metadata-only session still uses its capture, and a database used only for lookup cannot suppress work. Unresolved or ambiguous titles are not treated as identity matches. This is session-level source precedence, not subtraction of two differently scoped token totals.
- **Tencent**: the JSONL transcript supersedes the extension log and the aggregate database for the same client.
- **General rule.** The dedup identity is the product's own stable event id (message id, response id, trace+span, event id, cumulative-total watermark). File position or a synthetic timestamp bucket is a fallback only and is unstable under append — flag or avoid it. A globally unique embedded id must not be namespaced by file or database, or fork copies will not collapse.

## Limits and unimplemented variants

### Genuinely unread or deliberately not reported

- **`openclaw`** — mirrored Codex app-server rollouts and `.zst` archives are not read; the OpenClaw reader decodes neither.
- **`zed`** — a `zstd` thread is decoded only through a locally installed `libzstd`; with no library it is reported through a `note`, never counted as empty.
- **`freebuff`**, **`kiro` IDE/globalStorage/SQLite**, **legacy `commandcode`/`zcode` without a `usage` block** — estimated-only and deliberately not reported.
- **`crush`**, **`warp`** — cost-only; no token figure exists to report.
- **Copilot** — the OTEL and desktop lanes cannot yet be reconciled exactly, so partial OTEL coverage of a desktop lifetime is **stated, not subtracted**.
- **Group E** — a fresh install with no export/capture yields nothing; the prerequisite is a hard condition, and Pulse's own `UsageImports/<client>` folder is the supported way to drop a file in.

### Carried as partial or unclassified rather than guessed

- **`devin-cli`** — shown as **Devin**, not "Devin CLI". The store is `~/.local/share/devin/cli/sessions.db`, and that `cli` is Devin's own directory layout rather than a product marker: measured on a Mac with only Devin **Desktop** installed and no `devin` binary on `PATH`, the database was being written anyway — Desktop embeds the same core and starts it as a CLI (`init_cli`, `binary=devin`, `backend_type=windsurf` on every session). The database cannot settle which client drove it, so the name does not claim one; `devin-desktop` stays a separate client because its evidence, an `acp-events` capture tree, belongs to Desktop alone. Splitting these rows by `backend_type` is **not** done: one machine's sessions all carrying `windsurf` is a one-sided observation, not an established mapping.

- **`antigravity-cli` / `antigravity-ide`** — the spec named `antigravity-cli/conversations` alone, and that is not where the Antigravity **IDE** writes: measured on a Mac with the IDE installed, that folder was absent while `antigravity/conversations` held 38 readable generations (3.3M tokens, `gemini-3.8-flash`), so the client silently contributed nothing. They are **two clients sharing one reader, never one client reading both** — the same store shape written by different products, so pooling them would put one figure on screen for two things. The spec's own path is kept rather than repointed, and a root that does not exist yields no records. `AntigravityRootsTests` pins the split, including that the two share no root. `#1` is not counted (its "fixed system prompt" reading is reverse-engineered, not established) and the unknown `#9.#10` bytes are never decoded into a time; every record is partial because no whole-usage total reconciles the counted fields.
- **`hermes` / `droid`** — with a positive cache, the reported input is unclassified and the cache is not added; the record is partial. Neither is treated as Anthropic-independent.
- **`goose`** — no reasoning counter and no cache columns; the `total − input − output` remainder is unclassified, not derived into reasoning.
- **`qwen` / `opencodereview`** — the cache relation is read from the documented `usageMetadata` or settled by the store's own total; where a reported total cannot settle it the line is partial (Qwen) or skipped with the remainder partial (OpenCodeReview).
- **`zcode` legacy** — a bare total with no per-kind split is unclassified.
- **Cursor / Trae** — JSON and CSV coverage is a known subset; a file with no declared account is an **unknown scope**, and an event with no id creates no session rather than a synthetic one.

### Evidence

- **No client carries `hasCapturedValidation` beyond the seven legacy readers**, and a reader that reports `notes` has not been live-validated across every store it might meet. The suites assert the declared contract with synthetic stores; they are not a statement that every client passed on a real machine.
