# Changelog

What each release changed, written for somebody deciding whether to install it.

This file is the source for both the GitHub release page and the text Sparkle
shows in the update window — see [Scripts/changelog.py](Scripts/changelog.py).
Add the entry **before** tagging, in the small grammar the converter knows:
bullets, `**bold**`, `` `code` `` and `[links](https://example.com)`.

## 1.8.1

**中文**

**改进与修复**

- **连不上 GitHub 也能自动更新。** 检查更新前先试一下 GitHub，连不上就改走 update.qunqin.org 中转；检查或下载失败时，马上换另一条线路再试一次。安装包都带签名，Pulse 只装签名对得上的，中转改不了它。
- **更新说明只显示一种语言。** 跟随 Pulse 的语言（跟随系统时按系统语言）：中文显示中文，其他语言显示英文。
- **调整面板外观不再重新拉取用量。** 改面板大小、间距、玻璃效果等外观设置时，只重新排版，不再向所有服务商重新请求一遍。
- **保存的密钥不会再互相覆盖。** 设置里保存密钥和后台续期 DeepSeek 控制台登录同时发生时，其中一个可能被冲掉；你刚删掉的 DeepSeek 登录也可能被续期写回来。都已修好。
- **钥匙串授权弹窗不再拖住刷新。** 读取 Claude Code 登录最多等 60 秒，没人点就改用其他方式，不再让所有服务商的刷新一直等着。
- **月报的大数字不再被切掉一块。** 9、5 这类数字的右边之前会被削平。
- **设置页布局。** 「位置」一行在窗口不够宽时，选项换到下一行，不再把说明挤成一个字一行；月报窗口的订阅价格输入框缩短到合适的宽度。

**English**

**Changed and fixed**

- **Updates arrive even where GitHub is out of reach.** Pulse tries GitHub before each check and goes through update.qunqin.org when it does not answer; a check or download that fails is tried again at once the other way. Every update is signed and Pulse installs only what carries its signature, so the relay cannot change it.
- **Update notes in one language.** They follow Pulse's language (the system's, when Pulse follows it): Chinese in Chinese, English for every other language.
- **Changing how the panel looks no longer refetches usage.** Size, spacing, glass and the other look settings now only lay the panel out again instead of asking every provider afresh.
- **Saved keys no longer overwrite each other.** Saving a key in Settings while DeepSeek's console sign-in was being renewed in the background could lose one of them, and a renewal could bring back a DeepSeek sign-in you had just removed. Both fixed.
- **A Keychain prompt no longer holds up refreshing.** Reading Claude Code's sign-in waits at most 60 seconds, then falls back to the other routes instead of keeping every provider waiting.
- **The recap's big numbers are no longer clipped.** The right side of a 9 or a 5 was cut off flat.
- **Settings layout.** The Position row puts its choices under the label when the window is too narrow for both, instead of squeezing the description to a character a line; the recap window's price field is now the width of a price.

## 1.8.0

**中文**

**新功能**

- **月报和年报。** 把一个月或一年的 AI 编程记录做成一组可以分享的卡片：总览海报、陪你干活的工具、日历、一天里的时段、订阅回本，最后是一张成绩单。年报另有十二个月的日历和每月对比。在「设置 › Token 消耗」里点「查看九月的月报」或「查看 2026 年报」打开，可以保存、拷贝或分享图片。数据只来自这台 Mac 上的记录；缺的数据不画，不会用 0 补。
- **回本卡由你填价格。** 在月报窗口里填上每月订阅价，就能看到用出了几倍；不填就没有这张卡。项目名默认显示，可以一键隐藏。
- **月报好了可以提醒你。** 每月初提醒一次上个月的月报，点开直接看。在「设置 › 通知」的「月报生成时」，默认关闭。
- **Token 活动图。** Token 消耗面板新增最近十二个月的用量图，可以按每天（一格一天）、每周或累计总量来看，鼠标指上去显示当天或当周的数字。

**改进与修复**

- **会话列表更干净。** Claude Code 的子代理记录并入它所属的会话，同一个会话不再重复出现好几次；Codex 会话用你真正说的第一句话作标题，自动审查的会话标为「Codex 自动审查」，标题里不再出现链接，也不会拿文件名当标题。
- **项目名更准确。** 在仓库的工作树里干的活算在仓库名下；Codex 桌面版和 DeepSeek 的临时文件夹不再被当成项目。
- **Gemini CLI 等十个图标显示正常。** 之前 macOS 画不全它们，Gemini CLI 只剩一个点。
- **月报窗口打开时也显示 Dock 图标**，和设置窗口一样。

**English**

**New**

- **Monthly and yearly recaps.** A month or a year of AI coding as a set of cards to share: an overview poster, the tools that worked with you, the calendar, your hours, whether your plan paid for itself, and a closing scorecard. The yearly recap adds twelve small calendars and a month-by-month comparison. Open it from Settings › Token spend with View September recap or View 2026 recap, then save, copy or share the images. Everything comes from this Mac's own records; what is missing is left out, never drawn as zero.
- **A payback card at your price.** Type your monthly plan price in the recap window to see how many times over you used it; leave it empty and the card is left out. Project names are shown by default and can be hidden in one click.
- **A note when the recap is ready.** Once a month, early in the month, for the month that ended; clicking it opens that recap. In Settings › Notifications, off by default.
- **Token activity.** The Token spend pane charts the last twelve months by day (a square per day), by week or as a running total, with the day's or week's figure under the pointer.

**Changed and fixed**

- **Cleaner session lists.** Claude Code's subagent transcripts join the session they belong to, so one session no longer appears several times; Codex sessions are titled from the first thing you actually said, automatic reviews are marked Codex review, and titles no longer show links or fall back to a file name.
- **Better project names.** Work in a repository's worktree counts under the repository; Codex Desktop's and DeepSeek's scratch folders are no longer taken for projects.
- **Gemini CLI and nine other icons draw properly.** macOS drew them incompletely, Gemini CLI as a single dot.
- **The Dock icon also shows while the recap window is open**, as it does for Settings.

## 1.7.3

**中文**

**新功能**

- **设置打开时显示 Dock 图标。** 设置窗口被别的窗口挡住后，可以从 Dock 或 ⌘-Tab 找回来；窗口关上，图标随之消失。在「设置 › 通用」的「应用」一组里，默认打开。

**改进与修复**

- **Token 消耗更准确。** Codex 桌面版的子任务会带上主任务至今的全部记录，之前被当成子任务自己的用量重复计算，Codex 的数字因此严重偏高，现已去掉；已归档的 Codex 会话也会计入。Claude Code 保留一小时的缓存写入按官方的两倍输入价计算，OpenAI 的长上下文请求按长上下文价格计算。Devin CLI、OpenCode、Codebuff 和 Copilot 各有一处重复计算，已修正。更新后第一次打开会重新读取一遍本机记录。
- **Token 分类更好懂。** 分为「新内容」「缓存命中」「输出」三类，缓存写入算在新内容里。工具没有记录缓存时显示「未记录」，不再显示 0 或 0%。
- **卡片上的统计按日历计算。** 「最近 7 天」「最近 31 天」就是日历上的这些天，休息一阵回来不会再显示休息前的数字。没有价格的模型显示「—」，不再显示 $0.00。连续使用天数按全部记录计算，当天还没用也不会清零。「最常用模型」改名为「用量最多的模型」。
- **其他修复。** 删除账号后，正在进行的登录续期不会再把登录写回来；OpenCode 换了控制台账号后，卡片不再显示上一个账号的记录；登录或会话失效时会提示重新登录，不再一直显示旧数字；只有额外账号时也会按你设定的刷新间隔刷新；关掉窗口启动器后不再频繁唤醒；OpenCode Go 的月度窗口不再按 30 天算；服务商返回异常数据时不会再让 Pulse 崩溃。
- **中文翻译更自然。** 简体和繁体中文统一用「服务商」「账号」，诊断、集成和刷新设置里的句子也改得更顺。

**English**

**New**

- **A Dock icon while Settings is open.** A settings window another app has covered can be found again from the Dock or with ⌘-Tab; the icon goes when the window closes. In Settings › General, under Application, on by default.

**Changed and fixed**

- **More accurate token spend.** Codex Desktop's sub-agents start with their parent's whole history, which was counted again as their own work and made Codex's figures far too high; that copy is now left out, and archived Codex sessions are counted. Claude Code's one-hour cache writes are priced at twice the input rate, as Anthropic bills them, and OpenAI's long-context requests at the long-context rate. Devin CLI, OpenCode, Codebuff and Copilot each counted something twice; fixed. The first launch after updating reads this Mac's records again.
- **Token kinds that read plainly.** Fresh input, cache hits and output, with cache writes counted as fresh input. A tool that records no cache shows Not reported rather than 0 or 0%.
- **Card figures follow the calendar.** Last 7 days and Last 31 days are those calendar days, so coming back from a break no longer shows the days before it. A model with no price shows a dash rather than $0.00. Streaks count your whole history and no longer drop to zero before you have worked today. Favourite model is now Most tokens.
- **Other fixes.** Removing an account no longer lets a renewal still in flight write its login back; switching OpenCode console accounts no longer leaves the card on the old account's history; a lost sign-in asks you to sign in again instead of showing the last figures; a rail of added accounts alone follows the refresh interval you set; a switched-off window starter no longer wakes the app every few seconds; OpenCode Go's monthly window is no longer taken as 30 days; and a malformed reply from a provider can no longer crash Pulse.
- **More natural Chinese.** Simplified and Traditional Chinese settle on one word each for provider and account, with plainer sentences across diagnostics, integrations and refresh settings.

## 1.7.2

**中文**

**新功能**

- **服务状态。** Codex、Claude Code 和 DeepSeek 的设置页新增「服务状态」，照各自官方状态页的样式显示：每一项现在是否正常、过去 90 天每天一根竖条，以及状态页公布的可用率。Codex 显示 status.openai.com 的 Codex 分组，Claude Code 和 DeepSeek 显示各自状态页上的全部项目。打开设置页时读取，开着时每 5 分钟更新一次。
- **服务出故障时通知。** 设置 › 通知新增「服务出故障时」，默认关闭。打开后每 5 分钟检查一次你已开启的 Codex、Claude Code、DeepSeek，只在和工具相关的项目（Codex 分组、Claude Code 与 Claude API、DeepSeek 的 API 服务）出故障、变严重或恢复时各通知一次。以各自状态页的公布为准。

**改进与修复**

- **打开「关于」时立即检查更新。** 版本那一行显示的是此刻的结果，不再是上一次定时检查的结果。
- **更省资源。** 读取各工具的用量记录、汇总 Token 消耗和面板跟随鼠标时，少做了很多重复的工作。

**English**

**New**

- **Service status.** Codex's, Claude Code's and DeepSeek's settings gain a Service status section drawn the way each provider's own status page draws it: whether each part is up now, a bar a day for the last 90 days, and the uptime the page reports. Codex shows status.openai.com's Codex group; Claude Code and DeepSeek show everything on their pages. It is read when the pane opens and every five minutes while it stays open.
- **Notifications when a service is down.** Settings › Notifications gains When a service is down, off by default. Once on, it checks the Codex, Claude Code and DeepSeek you have switched on every five minutes and notifies once when what the tool runs on (the Codex group, Claude Code and the Claude API, DeepSeek's API services) goes down, gets worse or comes back — as each provider's status page reports it.

**Changed and fixed**

- **Opening About checks for an update right away.** The version row shows the answer now, not whatever the last scheduled check said.
- **Lighter on your Mac.** Reading each tool's usage records, adding up token spend and following the pointer on the panel all do much less repeated work.

## 1.7.1

**中文**

**新功能**

- **Codex 降智迹象。** 设置 › Codex 最下面新增「降智迹象」，只读本机的 Codex 记录，不发任何请求：每个模型有多少长回复的推理恰好停在 516、1,034、1,552 等位置（像被强行掐断，超过 5% 标为「疑似降智」），以及有没有哪一轮在你没改设置的情况下被换了模型、调低了推理强度或缩短了上下文。这些只是迹象，不是定论——Codex 不会记录服务器实际用了哪个模型。
- **DeepSeek 读取官网用量。** 在 DeepSeek 设置的「DeepSeek 控制台」里点「读取」，Pulse 会从浏览器（Chrome、Edge、Brave、Arc 等）的登录状态读取整个账号最近 30 天的用量：每天的花费和 Token、各模型占比和缓存命中率，金额用账号自己的币种。没有填 API Key 时也能用它读余额。

**改进与修复**

- **横放面板时，「百分比放在圆环右边」和「数字显示在圆环上方」同时打开，百分比不再跑到圆环左边；打开「距离重置的时间」时，数字也不再贴着外圈。** 感谢 [@tyrival](https://github.com/qunqin24/Pulse/issues/73) 反馈。
- **卡片在屏幕放不下时可以滚动。** 面板横放在屏幕中间附近时，展开的卡片不会再被屏幕边缘截掉。

**English**

**New**

- **Signs of a weaker Codex model.** A new Signs of a weaker model section at the bottom of Codex's settings reads this Mac's Codex records and sends nothing: for each model, how many long replies had their reasoning stop at exactly 516, 1,034, 1,552 and so on — as if cut off; over 5% is marked Possibly weakened — and whether any turn ran on a different model, lower reasoning or a smaller context without you changing the settings. These are signs, not proof: Codex doesn't record which model the server actually used.
- **DeepSeek usage from its console.** Press Read under DeepSeek console in DeepSeek's settings and Pulse uses your browser's sign-in (Chrome, Edge, Brave, Arc and other Chromium browsers) to read the whole account's last 30 days: spend and tokens per day, each model's share and cache hit rate, in the account's own currency. It also reads the balance when no API key is set.

**Changed and fixed**

- **Lying across, with Figures beside the rings and Figure above the ring both on, the percentage no longer jumps to the left of the ring; with Time until reset on, figures no longer crowd the outer arc.** Thanks to [@tyrival](https://github.com/qunqin24/Pulse/issues/73) for the report.
- **A card scrolls when the screen cannot hold it.** With the panel lying across near the middle of the screen, an open card is no longer cut off at the screen's edge.

## 1.7.0

**中文**

**新功能**

- **详细卡片。** 在账号设置里为某个账号打开「详细卡片」，鼠标移到它的圆环上时，卡片会多显示套餐、更新时间、最近的用量和缓存命中率，以及额度大约值多少钱。Claude Code 和 Codex 还会显示提示缓存还剩多久，多个对话同时进行时显示最紧急的那个。
- **按模型看用量。** 设置 › Claude Code / Codex 的「用量记录」下新增「模型」卡片：每个模型的用量占比、缓存命中率，以及最近 24 小时每秒输出多少 token；Codex 还有首字延迟。
- **提示缓存列表。** Claude Code 和 Codex 的设置页列出每个仍有缓存的对话，以及缓存还剩多久。
- **OpenCode Go 读取官网记录。** 在 OpenCode Go 的设置里读取浏览器的登录状态后，Pulse 会直接从官网控制台读额度和每一次请求的记录，覆盖所有设备，金额是实际扣费。
- **面板可以横向自由摆放，也可以吸附在屏幕底部。** 原来的「自由」改名「竖向自由」，新增「横向自由」；吸附在底部时面板贴着屏幕最底边，可以放在程序坞两边的空白处。感谢 [@GinWU05](https://github.com/qunqin24/Pulse/issues/70) 提议并实现横向自由摆放。

**改进与修复**

- **Claude Code 的用量不再重复计算。** 继续或分叉一段对话时，新记录会带上一份之前的历史，Pulse 之前把这份复制也算了进去，用量和花费因此偏高，多的可达三成左右。
- **Claude Code 的输出 token 不再少算。** 一条回复会分几行写进记录，之前只读了第一行，输出少算了约四分之一，额度价值也因此偏低。
- **额度价值推算更稳、更准。** 只算到读取额度的那一刻；周期开头那段不再漏掉；用量不足 5% 时不显示，避免整数百分比带来的大幅跳动；发现账号在别的设备上也在用时，这个周期不再推算并说明原因。
- **OpenCode 2 的记录能读到了。** 升级到 OpenCode 2 之后，Token 消耗里看不到新的用量。
- **Token 消耗在后台读取。** 打开开关后 Pulse 会自动在后台读取并保持更新，打开页面直接显示，关掉设置窗口也不会丢掉。
- **菜单栏图标换成 Pulse 的标志，菜单里的用量面板改为开关，默认关闭。**

**English**

**New**

- **A detailed card.** Turn on Detailed card for an account in its settings and its hover card adds the plan, when it was updated, recent usage and cache hit rate, and roughly what each limit is worth. Claude Code and Codex also show how long the prompt cache has left — the most urgent conversation when several are running.
- **Usage by model.** Under Usage history in Claude Code's and Codex's settings, a new Models card shows each model's share, cache hit rate and output tokens per second over the last 24 hours; Codex also shows the wait for the first token.
- **Prompt cache list.** Claude Code's and Codex's settings list every conversation still holding a cache, and how long it has left.
- **OpenCode Go from its own console.** Read the browser sign-in in OpenCode Go's settings and Pulse reads the limits and every request straight from the console — every device, with what each request was charged.
- **Float the panel lying across, or dock it to the bottom of the screen.** Free is now Free upright, beside a new Free across; docked to the bottom the panel sits on the screen's very edge, in the empty space either side of the Dock. Thanks to [@GinWU05](https://github.com/qunqin24/Pulse/issues/70) for proposing and building the lying-across placement.

**Changed and fixed**

- **Claude Code's usage is no longer counted twice.** Resuming or forking a conversation starts a new transcript with a copy of the old history, and Pulse counted the copy too — usage and cost read high, by as much as about a third.
- **Claude Code's output tokens are no longer undercounted.** A reply is written over several lines and only the first was read, missing about a quarter of the output — and of what each limit is worth.
- **Steadier, more accurate value estimates.** Spending counts up to when the limit was read; the start of a window is no longer dropped; nothing is shown under 5% used, where whole-number percentages made it swing; and a window being used on another device is not estimated, with the reason shown.
- **OpenCode 2's usage is read.** After upgrading to OpenCode 2, its new usage was missing from Token spend.
- **Token spend reads in the background.** With it on, Pulse keeps it up to date and the page opens on figures, even after the settings window was closed.
- **The menu bar shows Pulse's own mark, and the usage panel in its menu is now a switch, off by default.**

## 1.6.1

**中文**

**新功能**

- **额度重置后自动开始新窗口（可选）。** Claude Code 和 Codex 的用量窗口，要等重置后你发出第一条消息才开始计时。在账号设置里打开「自动开始新窗口」，Pulse 会在每次重置后不久、你设定的时间段内，通过服务商自己的命令行工具发一句「hi」，让窗口从那一刻起算。默认关闭；这不是 Anthropic 或 OpenAI 提供的功能，可能被视为绕过用量限制，打开前会请你确认。

**改进与修复**

- **新图标。** 一笔画成的 P：竖笔是面板贴着的屏幕边，荧光绿的圆肚子是一个还没合上的用量环。在 macOS 26 上带液态玻璃效果，并跟随深色、透明和着色图标样式。
- **开着液态玻璃、面板吸附在屏幕边时，圆环之间的空白处也能拖动了。** 此前只能按住圆环拖。设置里「开启后只能按住圆环拖动」这句提示也随之去掉。感谢 [@annsyun](https://github.com/qunqin24/Pulse/issues/68) 反馈。

**English**

**New**

- **Start usage windows after a reset (optional).** Claude Code's and Codex's windows only start at your first message after a reset. Turn on Start windows automatically in the account's settings and Pulse sends a single "hi" through the provider's own command-line tool just after each reset, within the hours you choose, so the window starts then. Off by default. It is not a feature of Anthropic or OpenAI and may be treated as getting around usage limits, so it asks you to confirm first.

**Changed and fixed**

- **A new icon.** A P drawn in one stroke: the stem is the screen edge the panel docks to, the lime bowl a usage ring not yet closed. On macOS 26 it is Liquid Glass and follows the dark, clear and tinted icon styles.
- **With Liquid Glass on and the panel docked to an edge, it can be dragged from between its rings**, not only by a ring. The settings caption saying so is gone. Thanks to [@annsyun](https://github.com/qunqin24/Pulse/issues/68) for reporting it.

## 1.6.0

**中文**

**新功能**

- **菜单栏显示用量。** 在 设置 › 通用 打开「在菜单栏显示用量」，菜单栏图标旁会显示用得最多的那个圆环，也可以指定某个账号。样式可选数字、迷你圆环，或「分项」并排显示 5 小时与每周额度（`5h/9%  周/15%`）；超过警示线时变红。默认关闭。
- **菜单栏用量面板。** 点开菜单栏图标，顶部是「概览」和每个账号的标签：概览列出所有账号的用量与重置时间；账号标签里有各项额度的进度条、套餐、更新时间、Codex 重置券与额度余额，开启「Token 消耗」后还有今天、最近 31 天、单日最多、累计的花费估算和每日柱状图。还可以一键打开服务方的官方用量页，或按 ⌘R 立即刷新。
- **只用菜单栏。** 菜单里新增「显示悬浮面板」开关，不喜欢屏幕边上胶囊的可以直接关掉。
- **再次打开 Pulse 会弹出设置。** Pulse 在后台运行时，从「应用程序」或聚焦搜索再打开它，会直接弹出设置窗口；就算面板和菜单栏图标都隐藏了，也不会找不到。

**改进与修复**

- **液态玻璃下，卡片的尾巴和卡片融为一体。** 此前尾巴在花哨背景上会像单独贴上去的一块水晶。
- **Grok 额度用到 100% 时会算作已用完**，和其他服务一致，会发出「额度用完」的通知。
- **删除额外账号时，会清掉它的所有设置**（小机器人外观、余额提醒等），不再残留。

**English**

**New**

- **Usage in the menu bar.** Turn on Show usage in the menu bar in Settings › General, and the menu bar icon shows the fullest ring — or an account you pick — as a figure, a small ring, or Split: the five-hour and weekly limits side by side (`5h/9%  Wk/15%`), red past the warning line. Off by default.
- **A dashboard in the menu bar menu.** Tabs across the top: an Overview of every account's figure and reset, and one tab per account with each limit's bar, the plan, how fresh the reading is, Codex's reset credits and credits left, and — with Token spend on — today, the last 31 days, the busiest day and all time as estimated cost, with a daily chart. Plus a link to the provider's own usage page and Refresh (⌘R).
- **Menu bar only.** Show floating panel is now in the menu, so the rail can be switched off in one click.
- **Opening Pulse again opens Settings.** A double-click in Applications or Spotlight while Pulse runs brings up Settings, so hiding both the panel and the menu bar icon is never a dead end.

**Changed and fixed**

- **With Liquid Glass, the card's tail is part of the card.** It used to read as a separate crystal over a busy backdrop.
- **Grok's pool counts as spent at 100%**, like every other provider, so the spent notification fires.
- **Removing an added account clears all of its settings**, including its animated mark and low-balance alert.

## 1.5.2

**中文**

**改进与修复**

- **新版 ChatGPT 桌面 App 也能读到 Codex 额度重置券了。** ChatGPT 26.924 把自带的 codex 换了位置，1.5.1 找不到；现在新旧两个位置都会找。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 定位。
- **卡片上显示最近一张重置券的到期时间**，精确到分钟，就在券的数量下面。

**English**

**Changed and fixed**

- **Codex's limit reset credits are read with the newer ChatGPT desktop app too.** ChatGPT 26.924 moved the codex it ships, and 1.5.1 didn't find it; both places are looked in now. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for tracking it down.
- **The card shows when the next reset credit expires**, to the minute, under the count.

## 1.5.1

**中文**

**新功能**

- **扩展可以显示余额。** 扩展除了报额度，现在也能报账户余额（金额和币种），适合 API 中转站。圆环可以像 API 服务一样选「自上次充值起 / 只看余额 / 我的预算」，也能设置低余额提醒。中转站的例子见 [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md)。感谢 [@Zoltan-code](https://github.com/qunqin24/Pulse/issues/40) 提议。

**改进与修复**

- **密钥输入框旁加了显示按钮。** 点小眼睛可以看到输入的内容，方便核对；换到别的服务时会自动重新隐藏。
- **API 服务设置页的「圆环计算方式」不再压住说明文字。** 这一行原来也叫「环上显示」，和面板组里的同名设置分不清，现在改了名。
- **只装了 ChatGPT 桌面 App 时，也能读到 Codex 额度重置券。** 此前 Pulse 不会去 App 里找自带的 codex，卡片一直显示「不可用」。找不到 codex 时，现在会直接显示「找不到 codex」。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 反馈。

**English**

**New**

- **Extensions can report a balance.** Besides limits, an extension can now report the money left in an account, as an amount and a currency, which suits API relays. Its ring takes the same three choices as an API account's — since top-up, balance only, my budget — and it can warn when the balance runs low. A relay example is in [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md). Thanks to [@Zoltan-code](https://github.com/qunqin24/Pulse/issues/40) for asking.

**Changed and fixed**

- **The key field has a show button.** Click the eye to see what you typed and check it; it hides again when you open another provider.
- **Ring measures no longer covers its own description** on an API account's settings page. It was also called Ring shows, the same as the Panel group's row for a different setting; it has a name of its own now.
- **Codex's limit reset credits are read when only the ChatGPT desktop app is installed.** Pulse never looked for the codex the app ships, so the card said Not available. When no codex can be found at all, it now says so. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for the report.

## 1.5.0

**中文**

**新功能**

- **新增 53 个服务商，共 77 个。** 阶跃星辰的 Step Plan，以及 ClinePass、阿里云百炼 Coding Plan 与 Token Plan、Qwen Cloud、美团 LongCat、Gemini、Kilo Code、Factory、Augment Code、Windsurf、Amp、Mistral、Moonshot、OpenAI API、xAI API 等 52 个。这 52 个参照 [CodexBar](https://github.com/steipete/CodexBar) 的实现移植，还没有用真实账号验证过；哪个用不了，欢迎提 issue。完整列表见 README。
- **扩展。** 自己写一个小程序放进扩展文件夹，就能让 Pulse 显示某个账号的用量，例如公司内部的额度接口。开启之前不会运行，Pulse 也不会交给它任何凭据。写法见 [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md)。感谢 [@guanbear](https://github.com/qunqin24/Pulse/issues/51) 提议。
- **订阅和 API 分开列。** 设置侧边栏和首次启动的服务选择窗口分成「订阅」和「API 与按量付费」两组，最上面是「已启用」，不用再从几十个服务里翻找。
- **每个 API 服务都能选圆环显示方式。** 此前只有 DeepSeek 可以：自上次充值起、只看余额、我的预算。现在 OpenAI API、Moonshot、New API 等报余额的服务都能各自设置。
- **Codex 卡片可以显示额度重置券。** 在 设置 → Codex 里打开「在卡片上显示额度重置券」，悬浮卡片会显示还剩几张；Codex 没有返回时显示「不可用」。默认关闭。感谢 [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) 提议。

**改进与修复**

- **用 npm 或 nvm 安装的 Codex，现在能读到它的 app server。** 从 Finder 或开机启动的 Pulse 找不到 `node`，app server 一启动就退出，重置券等数据一直读不到。Kiro、arkcli 等命令行工具也一并处理。
- **还没选服务时，菜单栏菜单第一项会提示去选。** 之前点了「以后再说」就没有任何提示说明面板为什么不见了。感谢 [@Drswith](https://github.com/qunqin24/Pulse/issues/66) 反馈。
- **面板窗口只按已开启的服务预留大小。** 此前按所有服务预留，服务一多，透明窗口会比屏幕高出许多。
- **「顺序」里只列已开启的服务。**
- **设置侧边栏加宽**，长名字不再被截断。

**English**

**New**

- **53 new providers, 77 in all.** StepFun's Step Plan, and 52 more including ClinePass, Alibaba Cloud Model Studio's Coding Plan and Token Plan, Qwen Cloud, LongCat, Gemini, Kilo Code, Factory, Augment Code, Windsurf, Amp, Mistral, Moonshot, OpenAI API and xAI API. Those 52 were ported by reading [CodexBar](https://github.com/steipete/CodexBar)'s providers and have not been checked against a live account yet; if one doesn't work for you, please open an issue. The full list is in the README.
- **Extensions.** A small program of your own, put in the extensions folder, can report one account's usage — an internal quota endpoint, say — and Pulse draws it as a ring. Nothing runs until you switch it on, and Pulse hands it no credentials. How to write one: [Docs/extensions.md](https://github.com/qunqin24/Pulse/blob/main/Docs/extensions.md). Thanks to [@guanbear](https://github.com/qunqin24/Pulse/issues/51) for proposing it.
- **Subscriptions and API accounts are listed apart.** The Settings sidebar and the first-run chooser group providers under Subscriptions and API and pay-as-you-go, with the ones you use under Enabled at the top.
- **Every API account chooses what its ring measures.** DeepSeek's three modes — since top-up, balance only, my budget — now apply to OpenAI API, Moonshot, New API and every other account that reports a balance, each set on its own.
- **Codex's card can show limit reset credits.** Turn on Reset credits on the card in Settings → Codex, and the hover card says how many are left, or Not available when Codex reports none. Off by default. Thanks to [@sanziliu](https://github.com/qunqin24/Pulse/issues/67) for asking.

**Changed and fixed**

- **A Codex installed with npm or nvm now reaches its app server.** Pulse launched from Finder had no `node` on its path, so the app server quit at once and reset credits never arrived. Kiro, arkcli and the other command-line tools are started the same way now.
- **The menu bar menu says to choose services when none are.** Dismissing the first-run chooser left no panel and nothing saying why. Thanks to [@Drswith](https://github.com/qunqin24/Pulse/issues/66) for reporting it.
- **The panel window is sized for the rings switched on.** It reserved room for every provider, which with dozens of them made the transparent window far taller than the screen.
- **Order lists only the accounts switched on.**
- **A wider Settings sidebar**, so long provider names are no longer cut short.

## 1.4.1

**中文**

**新功能**

- **Qoder 显示积分包的到期日。** 每个积分包有自己的到期时间，卡片会显示最早到期的那批，例如「10月18日 86 积分到期」，同一天到期的合并计算；`--json` 也新增了 `expiresAt` 和 `expiringAmount`。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 提议。

**改进与修复**

- **Qoder 体验版账号不再显示「未返回任何限额」。** 大陆站体验版会返回一个早已过去的重置时间，Pulse 据此把整份读数当作过期丢掉了；现在忽略这个日期，照常显示剩余积分。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 查清原因。
- **购买 Qoder 积分包不再被当成额度重置。** 买包后上限变大、用量比例骤降，之前会误发重置通知，小机器人也会庆祝；现在只有 Qoder 的重置时间往后推才算重置。
- **Qoder 确认账号没有积分时，不再显示旧的百分比。** 之前缓存会把上一次的读数顶回来，重启后和 `--json` 里也是。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/61)。
- **模型价格不用重启也会更新。** 价格表过期后，下次读取时重新下载；下载失败就继续用旧表，五分钟后可再试。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/60)。
- **小机器人的眼神和动作恢复原版幅度。** 之前为了让眼睛不贴边、身体不出圆环，Pulse 额外压缩了眼神、手势和大幅动作，摇头只剩一半幅度；现在按原版动画播放，动作大时眼睛可能贴着边缘，头顶可能短暂超出圆环。
- **鼠标移上胶囊时，小机器人依次转过去看。** 不再所有圆环在同一帧齐刷刷转向指针；每个各自晚一点注意到，约 0.4 秒平滑转过去。

**English**

**New**

- **Qoder shows when your credit packs lapse.** Each pack has its own end date; the card now shows the soonest, such as "Oct 18: 86 credits expire", with packs ending the same day added together. `--json` gains `expiresAt` and `expiringAmount`. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for asking.

**Changed and fixed**

- **A Qoder trial no longer shows "no limits reported".** The mainland site's trial replies with a reset date long past, and Pulse discarded the whole reading as expired. The date is now ignored and the remaining credits are shown. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for tracking down the cause.
- **Buying a Qoder pack is no longer read as a reset.** The larger limit made the used fraction drop, which sent a reset notification and set the bot celebrating. Only Qoder's reset date moving forward counts now.
- **An old percentage no longer covers Qoder saying an account has no credits.** The cache brought the previous reading back, after relaunch and in `--json` too. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/61).
- **Model prices refresh without restarting Pulse.** An expired price table is downloaded again on the next read; a failed download keeps the old one and may retry after five minutes. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/60).
- **The bot moves as the original animation does.** Pulse had been damping its glances, gestures and larger moves to keep the eyes off the edge and the body inside the ring, so a head shake lost half its sweep. They play at full size again: an eye may touch the edge, and the top of the head may briefly leave the ring.
- **The bots turn to an arriving pointer one after another.** Instead of every ring snapping to it in the same frame, each notices a moment later and turns over about 0.4 seconds.

## 1.4.0

**中文**

**新功能**

- **新增 Sub2API、New API、V2EX 和 Qoder，服务商增至二十四个。** 两个自建网关填入服务器地址和密钥即可读取余额或额度；V2EX 使用个人访问令牌读取 AI Chat 额度；Qoder 从浏览器读取 qoder.com 或 qoder.com.cn 的登录，显示积分额度，团队套餐的共享积分单独一个圆环。感谢 [@momusticks](https://github.com/qunqin24/Pulse/issues/59) 提议。
- **真正的液态玻璃。** 开启后面板是透明、带折射的 macOS 26 液态玻璃，不再是一层磨砂；文字改为白色，并新增「透明度」滑块，可按常用背景调节玻璃明暗。设置中的名称也改回「液态玻璃」。
- **时间圆环可以倒数。** 「距离重置的时间」的外圈可选「已过去」或「剩余」，剩余模式从满圈逐渐缩短到重置。感谢 [@Steven-oyjb](https://github.com/qunqin24/Pulse/pull/44)。
- **Kiro 与 ZCode 也会显示工作动画。** Pulse 读取它们在本机写下的会话记录判断任务是否进行中；ZCode 只在配置的接口属于智谱或 z.ai 时才驱动对应圆环。感谢 [@guanbear](https://github.com/qunqin24/Pulse/pull/56)。
- **设置按主题拆分成多个页面。** 外观、圆环与数字、位置与行为、通用、通知、网络与刷新各自独立；侧边栏搜索也能按设置项名称找到所在页面。
- **每个服务都有配置指南。** 设置里的「配置帮助」现在打开专门写给用户的页面：密钥或登录从哪里获取、填到哪里、常见报错怎么处理。

**改进与修复**

- **贴边时鼠标推到屏幕最边缘不再误判离开。** 之前开启自动收起时，指针贴着边缘会让胶囊反复展开又收起。
- **切换卡片更顺滑。** 高度不同的卡片之间切换时，新增的一行不再先于卡片出现在外面；快速扫过圆环时也不会看到空卡片。
- **小机器人不再偶尔瞬移。** 庆祝转圈或变形动作被中途打断时，身体会平滑过渡，不再在一帧内跳转。
- **Token 消耗：同名项目分开统计，无定价用量不再显示 $0.00。** 不同路径下的同名目录不再合并成一行；无法定价的会话和项目显示「—」或带 `*` 的小计。感谢 [@tech-zjf](https://github.com/qunqin24/Pulse/pull/57)（[#58](https://github.com/qunqin24/Pulse/pull/58)）。

**English**

**New**

- **Sub2API, New API, V2EX and Qoder bring the count to twenty-four providers.** Both self-hosted gateways read a balance or allowance from a server address and key you enter; V2EX reads its AI Chat allowance with a Personal Access Token; Qoder reads your qoder.com or qoder.com.cn sign-in from the browser and shows your credits, with a team plan's shared credits as a ring of their own. Thanks to [@momusticks](https://github.com/qunqin24/Pulse/issues/59) for asking.
- **Real Liquid Glass.** With glass on, the panel is clear, refracting macOS 26 Liquid Glass rather than a frosted layer. Text is drawn white, and a new **Transparency** slider sets how much the glass is dimmed for the backgrounds you usually work over. The setting is called Liquid Glass again in every language.
- **The window clock can count down.** The outer arc of **Time until reset** can show time elapsed or time remaining; remaining starts full and empties toward the reset. Thanks to [@Steven-oyjb](https://github.com/qunqin24/Pulse/pull/44).
- **Kiro and ZCode show activity too.** Pulse reads the session records they leave on this Mac to tell whether a turn is in flight; ZCode drives a ring only when its configured endpoint belongs to Zhipu or z.ai. Thanks to [@guanbear](https://github.com/qunqin24/Pulse/pull/56).
- **Settings are split by subject.** Appearance, Rings and figures, Position and behavior, General, Notifications, and Network and refresh each have their own pane, and the sidebar search finds a pane by the names of its settings.
- **Every provider has a setup guide.** **Setup help** now opens a page written for users: where the key or login comes from, where it goes in Pulse, and what each error means.

**Changed and fixed**

- **A pointer pushed against the screen edge no longer counts as leaving a docked rail.** With auto-collapse on, it used to open and close the rail over and over.
- **Switching cards is smoother.** An added row no longer appears outside a card that has not grown yet, and sweeping across the rings no longer shows an empty card.
- **The animated mark no longer jumps.** A celebration spin or a shape change interrupted mid-motion now eases into the next state instead of snapping in one frame.
- **Token spend keeps same-name projects apart and stops showing unpriced use as $0.00.** Directories with the same name at different paths are no longer merged, and sessions or projects that cannot be priced show `—` or a subtotal marked `*`. Thanks to [@tech-zjf](https://github.com/qunqin24/Pulse/pull/57) ([#58](https://github.com/qunqin24/Pulse/pull/58)).

## 1.3.1

**中文**

**新功能**

- **Kiro 成为第二十个服务商。** Pulse 通过 Kiro CLI 自带的 ACP 接口读取当前账号的方案与额度，无需额外登录或复制凭据；同一响应里的多个额度会分别显示，并保持稳定的账号身份。
- **浮动栏可以贴合刘海。** 顶部停靠时会围住刘海并延伸到屏幕边缘，在有刘海和无刘海的屏幕间移动时自动采用对应形状；警报提示改画在刘海下方，不会再被屏幕缺口遮住。
- **菜单栏图标可以隐藏。** 可只用浮动栏或全局快捷键进入 Pulse。设置会保证始终至少留有一个可用入口；`Command-,` 也会直接打开设置。
- **更多外观与动画开关。** 可关闭浮动栏警报颜色、CLI 活动动画和刷新动画，并让浮动栏两端保持与圆环一致的柔和曲线。

**改进与修复**

- **未选择显示的服务不会再偷偷读取。** Pulse 只扫描已监控服务的本机 CLI 活动；关闭显示的服务在设置里明确标为“未显示”，也无法从诊断页触发刷新。
- **Kiro 额度顺序变化不再打乱账号。** 额度身份改用 Kiro 返回的资源类型，不再依赖数组位置，因此重排后仍会保留各自的显示设置和历史。
- **修复辅助进程重启后的错误超时。** Codex 和 Kiro 的旧请求计时器不会再结束新一轮同编号请求，也不会让已经完成的请求留下延迟报错。
- **隐藏菜单栏图标时不会把自己锁在应用外。** 如果浮动栏不可用且快捷键没有成功注册，Pulse 会自动恢复菜单栏入口；首次选择服务前也不会允许隐藏唯一入口。
- **修正 GLM 服务图标与发布构建检查。** 两个 GLM 区域使用一致的服务标识；构建命令不再重复覆盖 Swift 语言模式，避免把无效警告当作发布失败。

**English**

**New**

- **Kiro is the twentieth provider.** Pulse reads the current plan and allowances through the ACP service built into Kiro CLI, with no extra sign-in or copied credential. Multiple allowances in one response remain separate and keep stable account identities.
- **The rail can berth around the notch.** A top-docked rail wraps the notch and reaches the screen edge, adapting as it moves between displays with and without a notch. Its alert cue is drawn below the cutout where it remains visible.
- **The menu bar icon can be hidden.** Pulse can be reached through the floating rail or global shortcuts alone. Settings always preserve at least one working entry point, and `Command-,` opens Settings directly.
- **More appearance and motion controls.** The docked alert colour, CLI activity animation and refresh animation can each be disabled, while the rail can keep ends softened to the rings' own curve.

**Changed and fixed**

- **Providers that are not selected are no longer read.** Pulse scans local CLI activity only for watched providers. A hidden provider is labelled “Not shown” in Settings and cannot be refreshed from diagnostics.
- **Kiro allowance ordering no longer changes account identity.** Allowances use the resource type returned by Kiro instead of their array position, preserving display choices and history when the response is reordered.
- **Fixed false timeouts after helper restarts.** Old Codex and Kiro request timers can no longer finish a newer request that reused the same identifier, or report a late failure after a request already completed.
- **Hiding the menu bar icon cannot lock the user out.** Pulse restores the menu bar entry if the rail is unavailable and no shortcut registered successfully, and keeps the sole entry visible until the first provider selection is complete.
- **Corrected the GLM provider marks and the release build check.** Both GLM regions now use a consistent provider identity, and build commands no longer override the package's Swift language mode and turn a redundant warning into a failed release.

## 1.3.0

**中文**

**新功能**

- **首次启动先由你选择要监控的服务。** Pulse 在选择完成前不会读取任何凭据，也不会开始监控。以后升级发现新的本机服务时只会提示，不会擅自开启；已有选择保持不变。
- **代理设置。** 网络可以继续跟随 macOS，也可以在设置中指定 HTTP、HTTPS 或 SOCKS5 代理。供应商请求、登录流程以及 Codex、arkcli 等辅助进程使用同一项选择。

**改进与修复**

- **Token 消耗改为明确选择后才读取。** 新安装默认关闭；开启后也只在查看该页面时扫描本机会话，离开页面或关闭设置会取消仍在进行的读取并释放结果。大型 JSONL 日志改为流式解析，避免为一次统计把整份文件载入内存；回到页面时会复用已经完成的结果，手动重新扫描除外。
- **八种小机器人有了各自完整的动作编排。** 日常、工作、刷新、鼠标响应和完成反馈按顺序播放，不再随机跳过招牌动作。所有日常动作与工作动作明确分开，空闲转圈不再冒出代表工作的彩带；只有「迟缓」会在深夜打瞌睡。
- **小机器人的眼睛在连续工作动画中仍保持完整。** 最终轮廓约束留出适合圆环尺寸的微小内边距，旋转和随机瞥视叠加时不会把半只眼睛裁掉。Kimi 的机器人蓝色也调亮，在小尺寸下更清楚。

**English**

**New**

- **Choose what Pulse may monitor before it starts.** A first-run picker makes the choice explicit. Pulse reads no credentials and starts no monitoring until it is saved. Later upgrades only suggest newly detected services; they never enable one on their own or disturb an existing choice.
- **Proxy settings.** Network traffic can keep following macOS or use a manually configured HTTP, HTTPS or SOCKS5 proxy. Provider requests, sign-in flows and helper processes such as Codex and arkcli all use the same selection.

**Changed and fixed**

- **Token spend is read only after an explicit opt-in.** It is off on new installs and scans local sessions only while its Settings pane is open. Leaving the pane or closing Settings cancels an unfinished read and releases its result. Large JSONL logs are streamed instead of loaded whole, while a completed result is reused when returning to the pane unless Rescan is requested.
- **Each of the eight bots now has a complete authored choreography.** Everyday, working, fetching, pointer-attention and completion scenes play every beat in order rather than randomly skipping signatures. Everyday and work vocabularies are separate across the whole cast, an idle spin no longer throws work ribbons, and only Sleepy may doze at night.
- **Eyes remain whole through sustained work animation.** The final silhouette bound reserves a small ring-sized inset, so stacked turns and glances no longer clip half an eye. Kimi's bot blue is lighter as well, keeping its face readable at this size.

## 1.2.1

**中文**

**修复**

- **修复 Codex 会让 CPU 空转的问题。** `codex app-server` 退出后，Pulse 还在读它那根已经关掉的管道。这种管道永远"可读"，所以读取回调会被不停地重复调用——一个核跑满，直到退出 Pulse 为止。而且 helper 每重启一次就多留下一条空转线程。感谢 [@ethan-ji](https://github.com/qunqin24/Pulse/issues/25) 把原因、堆栈和条件都查清楚了。

**新功能**

- **小米 Coding Plan 成为第十九个服务商。** 读取小米 MiMo 控制台上按月购买的 token 额度，有周期结束时间就一并显示，预付余额作为一行金额附在卡片上。凭据是浏览器里已登录的会话，不是 API key——平台发的 key 是买推理用的，控制台的账户接口一个都不认。账号上没有 Coding Plan 时会直说，而不是画一个 0%。
- **更新检查改为每两小时一次**，原本是一天一次。仍然只提示，不会自己安装。

**改进**

- **小机器人现在会看向屏幕里侧。** 胶囊贴在右边时看左边，贴在左边时看右边，拖到另一边会把视线挪过去而不是瞬间跳过去。之前那个偏移量比表情自带的朝向小得多，所以大部分时候还是在盯着屏幕边框。鼠标在面板上时，它优先看鼠标。
- **小机器人的眼睛不会再跑出脸外。** 表情自带的朝向、贴边偏移和随机瞥视叠加起来会把眼睛推出轮廓，被裁掉之后看上去像少了一只眼。
- **重写设置里小机器人相关的中文文案。** 之前是照着英文直译的。

**English**

**Fixed**

- **Codex no longer spins the CPU.** After `codex app-server` exits, Pulse went on reading its closed pipe. A pipe in that state is readable for ever, so the read callback was called again and again — one core, flat out, until Pulse was quit — and every restart of the helper left another spinning thread behind. Reported by [@ethan-ji](https://github.com/qunqin24/Pulse/issues/25), with the cause, the stack and the conditions already worked out.

**New**

- **Xiaomi Coding Plan is the nineteenth provider.** Reads the monthly token allowance bought on Xiaomi's MiMo console, with the period's end where it reports one, and the prepaid balance as a line on the card. The credential is your signed-in browser session rather than an API key — the platform's keys buy inference and answer none of the console's account routes. An account with no plan says so instead of drawing 0%.
- **Updates are checked every two hours** rather than once a day. Still offered, never installed on their own.

**Changed**

- **The bot now faces into the screen.** A rail docked right looks left, docked left looks right, and dragging it across sends the eyes over rather than snapping them. The old lean was far smaller than the glance drawn into each expression, so a mark spent much of its time staring at the screen edge. A pointer on the panel outranks all of it.
- **The bot's eyes stay inside its face.** The expression's own glance, the edge lean and the random glances stacked up and pushed an eye past the silhouette, where it was clipped — which read as a mark with one eye.
- **Rewrote the Chinese copy for the bot settings**, which had been translated word by word from the English.

## 1.2.0

**中文**

**新功能**

- **动画标记。** 可以把某个账号环里的供应商图标换成一个会动的小机器人，默认关闭，在该账号的设置页里逐个开启。它只说面板已经知道的事：该供应商的 CLI 正在跑、Pulse 正在取新读数、额度已用满、还没有读数、或者什么都没发生。开启动画标记的环不再画白色活动弧——转动的白弧和一个明显在干活的小机器人是同一件事画了两遍。
- **人格、形状与颜色。** 八种人格决定它播放哪些动作和节奏，默认自动分配，保证相邻的环是不同的角色；十八种身体形状可选，默认都是圆形；颜色默认取供应商品牌色，没有品牌色的会自动分配一个与邻居区分开的色相，也可以自己指定。三项都按账号设置。
- **它会对正在发生的事做出反应。** 眼睛跟随面板上的鼠标，被指着的那个会停下来倾听；干活时在"工作、生成、书写"之间切换，非工作时间干活会一边生气一边干；长时间没有任何 CLI 写入会无聊，深夜则犯困；额度重置时庆祝，一轮活干完时兴奋。重置的判定用的是通知系统同一条规则，与通知是否开启无关。
- **关于页加入项目地址。** 同时注明动画标记的移植出处。

**English**

**New**

- **Animated marks.** A ring's provider logo can be replaced by a small animated bot. Off by default, switched on per account in that account's settings pane. It says only what the panel already knows: that provider's CLI is running, Pulse is fetching a reading, the limit is spent, there is no reading yet, or nothing is happening. A ring drawing a mark no longer draws the white activity arc — a travelling arc and a bot that visibly gets to work are one fact drawn twice.
- **Personality, shape and colour.** Eight personalities decide which motions a mark plays and at what pace, dealt automatically so the ring beside it is a different character. Eighteen body shapes, round by default. Colour is the provider's brand where it has one, otherwise dealt to stand apart from its neighbours' hues, or chosen outright. All three are per account.
- **It reacts to what is happening.** The eyes follow the pointer across the panel, and the ring being pointed at stops to listen. Work alternates between working, generating and writing, with anger added out of hours. A machine that has been quiet for twenty minutes gets bored, and sleepy about it at night. A limit that resets is celebrated; a finished turn gets a cheer. The reset is recognised by the same rule the reset notification uses, whether or not notifications are on.
- **The project's address in About**, alongside credit for the animated marks' origin.

## 1.1.2

**中文**

**新功能**

- **更多 Token 消耗来源。** 新增 Gemini CLI、Cline、Roo Code、OpenClaw、GitHub Copilot 等本地记录读取，并支持 Cursor、Trae 等导出数据。部分来源需要先导出或捕获记录；可读格式及验证范围见[来源说明](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md)。
- **模型用量详情。** 点击模型可查看输入、输出、缓存读写、每日与每小时消耗，以及各 Agent 的贡献；明细表支持排序和分页。费用按公开 API 价格折算，不是订阅账单。
- **图表悬停读数。** 指向历史图表即可查看对应日期或小时的 token 数量，较短的柱形和零用量时段也能选中。
- **浮动栏菜单与全局快捷键。** 右键浮动栏即可打开设置；可自行设置快捷键，用于打开设置或显示、隐藏浮动栏。默认不绑定按键。
- **繁体中文、日语和韩语。** 界面与 README 新增三种语言，大数缩写使用各语言对应的单位。

**改进与修复**

- 补全仅由套餐商公布价格的模型计价，修复 Kilo CLI 的价格来源；日汇总、模型详情和会话金额保持一致。
- Antigravity IDE 读取自身的会话存储；Devin 记录不再误标为仅来自 CLI，已匹配的数据库与 Desktop 捕获只统计一次。
- 跨天汇总记录只计入所选区间；Command Code 回退对话后仍保留已经发生的消耗，重复记录不会重复计数。
- Token 消耗默认显示最近一周，并记住所选区间；缺失价格、不完整计数和不可用的小时明细会明确标注，旧缓存自动重读。
- 修复切换语言后设置侧栏变窄的问题，补充 Agent 图标并更新界面截图。

**English**

**New**

- **More token-spend sources.** Added local-record readers for Gemini CLI, Cline, Roo Code, OpenClaw, GitHub Copilot and more, plus exports from Cursor, Trae and others. Some sources require a prior export or capture. See [sources and validation coverage](https://github.com/qunqin24/Pulse/blob/main/Docs/token-spend-sources.md) for supported formats.
- **Model usage details.** Open a model to inspect input, output, cache reads and writes, daily and hourly usage, and contributions by agent. Detail tables support sorting and paging. Costs use published API rates and are not a subscription bill.
- **Chart hover values.** Point at a history chart to see the token count for a date or hour, including short bars and periods with no usage.
- **Rail menu and global shortcuts.** Right-click the floating rail to open Settings. Optional shortcuts open Settings or show and hide the rail; both are unassigned by default.
- **Traditional Chinese, Japanese and Korean.** Added three interface and README translations, with large-number abbreviations using each language's own units.

**Changed and fixed**

- Added pricing for models listed only by their plan vendor and corrected Kilo CLI's price source. Day, model and session amounts agree.
- Antigravity IDE reads its own conversation store. Devin records are no longer labelled CLI-only, and matched database sessions and Desktop captures count once.
- Cross-day aggregate records contribute only their in-range usage. Command Code rewinds retain consumption that already occurred, and replayed records are not counted twice.
- Token spend defaults to the last week and remembers the selected span. Missing prices, incomplete counts and unavailable hourly detail are identified; older caches are reread automatically.
- Fixed the Settings sidebar narrowing after a language change, added agent icons and updated screenshots.

## 1.1.1

**中文**

**新功能**

- **Devin 成为第十八个服务商。** 从 Chromium 浏览器会话读取每日、每周额度，无需钥匙串授权；无登录凭据时读取应用保存的带日期套餐。不同账户和组织的读数保持隔离。
- **Token 消耗统计。** 汇总 Claude Code、Codex、OpenCode、Kilo CLI、Grok Build、Kimi CLI 和 Devin CLI 的本机会话，按区间、Agent、模型、项目、会话和 token 类型查看。费用按公开 API 价格折算，不是订阅账单。
- **开发者集成。** 在设置中导出 Raycast 扩展及 tmux、sketchybar、终端脚本；`Pulse --json` 增加读数来源和账户设置链接。集成仅读取缓存。[配置指南](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md)。
- **连接诊断。** 查看最近检查、读数来源、缓存和回退结果，按原因修复连接；额外账户可原位重新登录。可复制不含账户详情或凭据的诊断信息。
- **变红阈值可调。** 可选 60%–90%，默认 75%；圆环、详情条和收起的胶囊保持一致，已耗尽状态仍优先。

**改进与修复**

- Claude Code 的 warning 不再被误判为额度耗尽；登录码、取消按钮和错误信息归属正确的服务商页面，切换页面不再串写凭据。
- 修复详情卡片展开、收起时沿胶囊漂移的问题。
- 跨天会话只计入所选区间；修正日志与数据库缓存更新、模型别名计价和自定义会话标题读取。
- Devin 旧快照按实际时间标注，过期窗口和超龄快照不再显示；额度变化纳入自适应刷新，异常浏览器存储长度不再导致崩溃。

**English**

**New**

- **Devin is the eighteenth provider.** Read daily and weekly quota from your Chromium browser session without a keychain prompt. With no credential, Pulse reads the app's dated saved plan. Account and organization boundaries are preserved.
- **Token spend.** Bring together local sessions from Claude Code, Codex, OpenCode, Kilo CLI, Grok Build, Kimi CLI and Devin CLI, grouped by span, agent, model, project, session and token kind. Costs use published API rates and are not a subscription bill.
- **Developer integrations.** Export a Raycast extension and tmux, sketchybar and shell scripts from Settings. `Pulse --json` now includes reading sources and account links; integrations only read the cache. [Setup guide](https://github.com/qunqin24/Pulse/blob/main/Docs/integrations.md).
- **Connection diagnostics.** Inspect checks, sources, cache use and fallback outcomes, with relevant repair actions and in-place reauthentication for added accounts. Copied diagnostics omit account details and credentials.
- **Configurable warning colour.** Choose where rings turn red, from 60% to 90% (default 75%). Rings, detail bars and the collapsed rail agree; exhausted limits still take precedence.

**Changed and fixed**

- Claude Code warnings no longer mean exhausted. Device codes, Cancel and errors stay with their provider; switching panes no longer lets login completion overwrite another provider's credential field.
- Fixed detail cards drifting along the rail as they open and close.
- Cross-midnight sessions count only their in-range work. Corrected log and database cache updates, model aliases and custom session titles.
- Devin snapshots retain their actual age; expired windows and over-age snapshots disappear. Quota changes participate in adaptive refresh, and malformed browser-storage lengths no longer crash Pulse.

## 1.1.0

- **A large balance no longer overflows the ring.** The rail shows ¥5k, ¥123k, $1.2M rather than the full figure, which did not fit and was being cut off — the exact balance is on the card and in Settings. It is always rounded **down**, so the ring never claims you have more than you do.

- **The rail no longer sits slightly too low until you touch something.** On most displays the panel is taller than the space macOS will grant it, and Pulse works out where to draw the rail from the position the window actually got. It was asking that question a moment too early — before the window was on screen, when the answer was still the position it had **requested** — so the rail was drawn about 76pt below where it belonged, and then jumped into place the first time any setting changed.

- **API balances are checked more often.** Pulse paces itself by watching this Mac — an agent writing to its transcripts, a figure that moved, you glancing at the rail — which is why it can be quick when you are working and quiet when you are not. But money spent through an API leaves no trace here, so DeepSeek and Command Code were always being left the full half hour: it waited because nothing had changed, and nothing appeared to change because it waited. Those two are now checked at least every five minutes. Everything else is unaffected, a Mac in low power or with the panel hidden still goes quiet, and a fixed interval you chose yourself still means what it says.

- **The provider list starts in alphabetical order.** It was in the order providers had been added over the months, which meant nothing to anyone reading it. If you have arranged the rail yourself, your arrangement is untouched.

- **Tell me when the credit runs low.** Providers that sell prepaid credit — DeepSeek and Command Code — get a **Warn below** figure in their own settings, and Pulse says so once when the balance falls under it. Money rather than a percentage, because these two report no allowance to take a percentage of; per provider rather than one figure, because ¥20 and $20 are not the same line. Off until you set one, like every other notification here. It is said once and not again until you top up — or until you move the line, which is a new question and gets a new answer.

- **Notifications about a prepaid balance say less, and say it correctly.** Credit that is bought does not reset and cannot be declared spent by arithmetic, so changing what the ring measures against no longer announces a reset, and a balance reaching 100% of a figure **you** set no longer claims the provider says you are out. Only the provider saying so does that.

- **DeepSeek is the seventeenth provider**, and the first one Pulse carries that reports no allowance at all — `GET /user/balance` says how much prepaid credit is left and nothing else. There is no quota, no window and no spend history to read, so the ring needs a denominator from somewhere and you choose which in DeepSeek's settings. **Since top-up** is the default and needs nothing from you: Pulse remembers the highest balance it has watched, and a balance that goes up can only be a top-up, so the ring starts again from full when you add credit. **Balance only** draws no ring at all and puts the money itself on the rail. **My budget** measures against a figure you type. The first two days on "since top-up" will read low — Pulse can only measure from the moment it started watching, and the card says which date that is.

- **智谱's row is now called "Zhipu".** The rail and the settings list are otherwise all Latin script, and one row in Chinese characters read as a different kind of thing rather than as another shop. The company, the storefront and the key it takes are unchanged — this is the name on the row, nothing else. Its sibling stays **z.ai**, which is that company's own spelling.

## 1.0.9

- **Command Code is the sixteenth provider.** It bills a credit balance in dollars rather than a token allowance, so the rings are money: the rolling 5-hour and weekly limits, your organisation's spend limits, and how much of this month's plan is gone. That last one is marked **estimated** on the card, and it is the one thing here Pulse has to infer — Command Code reports what is **left** of a plan's monthly credit but never what the plan grants, which is published on its pricing page instead. A plan Pulse cannot size shows no monthly row at all rather than a reassuring zero. Sign in by pasting a key, or let Pulse borrow the one `cmd auth login` already saved.

- **The panel can follow you between displays.** Switch on "Follow the active display" and the rail moves to whichever screen your pointer is on, keeping the same corner and the same distance down it. There is still only one rail — it is carried across, not copied onto every monitor — and it stays where you last dragged it if you leave the setting off, which is how it ships. "Active" means the display the pointer is on and nothing else: it does not chase other apps' windows around, and it asks for no extra permission to work out where you are.

## 1.0.8

- **The interface follows your Mac's language.** Pulse now declares that it speaks Chinese, which it always did — the translations shipped, macOS just was not told they existed, so a Mac set to 简体中文 got an English app. If that was you, this update switches over on its own; if you preferred it in English, Settings › Language still overrides. The Chinese copy has been rewritten throughout while we were in there.

- **Antigravity can show its two allowances as two rings.** The plan carries one budget for Gemini and a separate one for Claude and GPT, and until now a single ring could only follow whichever was busier — the other went unmentioned unless you hovered. Switch on "A ring for each model group" in Antigravity's settings and each gets its own ring, both under the Antigravity icon, both refreshing the one login. Off by default: an extra ring takes room on the rail, and most people want the one number.

- **智谱 and z.ai get a usage history**, read from the same statistics the console draws its own charts from. Unlike the history Pulse builds for Claude Code and Codex — which it works out by reading session files on this Mac — this one comes from the account, so it covers every machine you use it on. It counts tokens only: the figures behind it cannot be turned into money, and the card says so rather than printing a confident zero.

- **A second limit on the ring.** A thinner ring inside the first shows the next-fullest limit *of the same kind* — the 5-hour beside the weekly it belongs with — so both are readable without hovering. Where a provider splits its allowance by model, the two arcs come from the same allowance wherever it has a second limit to show: pairing one model's weekly with another's 5-hour would put two unrelated budgets on one mark. Off by default and switched on in Settings; the ring is the thing you read without stopping, and two arcs is twice as much to take in. Where a provider reports only one limit nothing is added.

- **The panel no longer slides out from under you as you pick it up.** On a display where the panel is taller than the space under the menu bar — which is most laptops — macOS quietly refuses the position Pulse asks for, and Pulse was then drawing the rail relative to a position the window never had. It jumped about one ring's worth on the first frame of a drag. It tracks the pointer exactly now.

- **The two GLM Coding Plan rows are now named for the shops** — **z.ai** and **智谱**. They were "Z.ai" and "GLM Coding Plan", which was a trap: both shops sell the plan under that same name, so anyone on the international plan picked the row named after their product and had their key sent to the mainland service, which of course refused it.
- **A refused key now says the key was refused.** These services answer with an ordinary HTTP 200 and put the verdict inside, and Pulse only recognised the English wording and two of the numbers — so the most common mistake of all, a key from the other one of the two shops, came out as "the service returned an error" and sent people looking for an outage that was not happening.

## 1.0.7

- **Pulse can tell you, instead of waiting to be looked at.** Three switches in Settings, all off until you turn them on. **Warn at** posts a notification when a limit passes 75, 80, 90 or 95% — whichever you pick — and again when the provider says it is spent. **When a limit comes back** says so once the window you were warned about has turned over, which is the moment you can start again. **When a reading stops arriving** is the one that is about Pulse rather than about usage: a failed check falls back to the last good figures, which is the right thing to show and also the reason the fault is invisible — the panel goes on displaying perfectly plausible numbers with only a "last read" time to give it away. It waits for three failures in a row and then says it once, with the same sentence the card would have shown you.
- **It says each thing once.** A limit already past the line when you switch this on is mentioned straight away — silence followed by a wall is not restraint — and then never again until it resets or gets worse. "Spent" is the provider's own word, never a rounding of ours. A reset is announced only on unambiguous evidence, so a rolling weekly allowance sliding down a few points is not mistaken for a window turning over. And a provider you have never set up, or an app that simply is not running, is not a failure to be reminded of on a timer.
- **Antigravity reads from the IDE too**, not only the desktop app. If Antigravity IDE is the one you have open, its ring said “Open Antigravity to see its usage” while the figures were sitting there for the asking. Both report the same thing — the Gemini and the Claude-and-GPT group, weekly and five-hour each.
- **Antigravity could pick the wrong helper and give up.** It runs more than one of these, only one of them answers, and Pulse asked the first it found and stopped.
- **Reorder the rail by dragging.** The arrows are still there — they are the precise way to move one place, and the only way that works from the keyboard — but with fifteen providers, moving the bottom one to the top was fourteen clicks. There is a Reset order button under the list for when a drag goes somewhere you didn't mean.
- **Volcengine**, bringing it to fifteen. The Ark Coding Plan and Agent Plan, personal and team, each with its five-hour, weekly and monthly windows. Two ways in: `arkcli`, using the login it already saved so there is nothing to paste, or a Volcengine access key pair for anyone who has keys but doesn't run the CLI here. With both set up it prefers the keys — the CLI carries a sign-in that can belong to a different account, and quietly showing the wrong account's limits is worse than either answer.
- **`Pulse --json`**, so the figures can go somewhere other than the panel — a tmux status line, sketchybar, Raycast, a shell prompt. It prints what the app last read rather than fetching, so polling it every second costs nothing and asks no provider anything; every account says when its figures were taken and how old they are. Nothing in the output is translated, so a script parsing it does not break when you change the interface language.
- **Settings has a search field**, since the sidebar now lists fifteen providers plus whatever accounts you have added. It matches the provider's name as well as your own label, so a second Claude subscription you called "work" is still found by typing Claude.
- **The Settings window opens bigger.** It was sized when the sidebar held four rows and had got to the point of appearing already scrolled in both columns.
- Notifications come with the standard notification sound. Silence them, or change anything else about how they arrive, in System Settings › Notifications › Pulse — the same place as every other app.

## 1.0.6

- **Grok**, read from the login Grok Build's CLI already stores — nothing to paste. One thing worth knowing before the ring confuses you: since June 2026 a paid Grok plan spends **one weekly pool across every Grok product** — the web chat, Imagine, voice, the API and the CLI alike — so this is what the account has spent this week, not what the CLI has. That is why it is called Grok rather than Grok Build.
- **Grok Bot**, which is a different limit despite the name. It comes with a Cursor plan rather than a SuperGrok one, so it is read with the login the Cursor editor already stores and carries the xAI mark to tell the two apart on the rail. It appears by itself only if the standalone app is installed; otherwise switch it on in Settings.
- **A second account of either.** Grok signs in with a device code, Grok Bot through Cursor's own sign-in page. Both ask for the narrowest access that can read a limit — never for permission to read or write your conversations.
- A card could print a window length the provider never reported. Some limits carry a length that only exists to sort the rows — a rolling week, a billing cycle — and when there was no reset time to show, that length was printed as though it were one.
- A provider with a single route named the wrong one in Settings. Every such provider but Cursor was described as "Antigravity's language server", about an app it had nothing to do with.

## 1.0.5

- **Claude Code read through the Claude desktop app.** If you work in the desktop app rather than a terminal, Pulse had no way to see your limits: the desktop app hands the CLI a token through its own environment and renews it itself, so the login Pulse was reading went stale and never came back, and it never renders a status line either. Pulse can now read the session the desktop app is signed in with — a new "Desktop app" choice under Read usage from, and the route `Automatic` falls back to once you have allowed it. It asks for the keychain once, at launch, so there is nothing to go and find in Settings.
- **The new route says why it can't answer**, rather than leaving the last reading in place with nothing but its "Last read" time to give it away — which is what makes a refresh look as though it did nothing. It says whether the desktop app is signed out, or whether it was the keychain that was refused.
- **A reading could go backwards.** A newer figure already on file could be replaced on screen by an older one that had just arrived, and a refresh that had been given up on could still overwrite the one that replaced it — including, for an added account, the renewed login itself.
- **GitHub Copilot no longer shows a red ring for paid overage.** Going past the included allowance with overage permitted is not being blocked, and it was being drawn as though it were.
- **Codex no longer marks the wrong model group as spent.** A group reporting "limit reached" could put the mark on another group's window entirely.
- Removing your only added account no longer leaves the rail empty.

## 1.0.4

- **GitHub Copilot**, bringing it to twelve. Signs in with a device code, so there is no token to paste — Pulse asks GitHub for permission to read your profile and nothing else, and never for access to your repositories. Shows the completions, chat and premium-request allowances your plan actually has.
- **Whether a limit will last.** A switch in Settings puts one line under each limit on the card: whether it is on course to outlast its window, and roughly when it runs out if it isn't. Off by default, and it stays quiet when the figures can't carry it — the time only appears when it falls before the reset, and it is rounded, because usage comes in bursts and a figure to the minute would be made up.
- **Show what's left instead of what's spent.** Another switch, which turns the figure and the ring over together so a limit reads "88% left" rather than "12% used". The colour still means how close you are, so a nearly empty ring is still red.
- **Claude Code's card names the plan** — "Max 5x", "Pro", "Team" — as every other provider's already did. The multiplier is part of it, since a Max 5x and a Max 20x are different products.
- **The panel could quietly stop refreshing** after running a long time, and only come back when you next started Claude Code in a terminal. It notices when its own readings have gone stale and asks again, recovers from a fetch that never returned, and refreshes when the Mac wakes as well as when the display does.

## 1.0.3

- **The panel can go on a second display.** Drag it across; it remembers which screen you left it on, and comes home if that screen is unplugged.
- **Four more providers**: the GLM Coding Plan and MiniMax, each with a separate entry for the international and the mainland service, since they are separate accounts with separate keys.
- **A second arc can show how far through the window the clock is**, so "80% used" can be read against how much of the window is left. Off by default, in Settings.
- **The figure can sit above the ring** instead of below it. Also in Settings.
- A provider that needs an API key is no longer switched on by itself — it waits in Settings rather than taking a place on the rail to ask for a key.
- One that has no key says so, instead of saying "Reading…" for ever.
- Claude Code no longer shows a limit that has already reset. If its saved login has expired and no session has run for a while, the stale window is dropped rather than shown with an old reset time.
- The update window now shows the release notes itself, rather than loading the GitHub page inside it.

## 1.0.2

- **Multiple accounts.** Sign in to a second Claude Code or Codex subscription and watch both at once, each with its own ring.
- **Cursor**, reported as the two pools its own account page shows.
- **Ollama Cloud**, from PcOffeeP's pull request — with the session read out of your browser rather than copied by hand.
- **The rail can dock along the top of the screen**, above the menu bar.
- **A colour of your own for any ring**, and the gap between rings is now adjustable.
- **Percentages can be switched off** on either rail.
- The rail opens with the last reading instead of sitting blank.
- The activity mark no longer keeps turning for a minute after a turn has ended.
- The API-key field in Settings lets go when you click away from it.
- A limit you have used never reads as 0% any more.
- Quitting Codex no longer takes Pulse down with it.
- A new app icon, drawn on Apple's icon grid.

## 1.0.1

- **OpenCode Go** and **Kimi Code**, bringing it to five agents.
- **Put the rings in your own order**, in Settings.
- **A refresh button on every provider's pane**, with the age of the reading beside it.
- A new install starts with the agents you actually have, rather than five rings that say "not configured".
- The panel can be dragged by any part of the capsule, not only by its rings.
- Clicking a ring refreshes the one you clicked, whatever order the rail is in.
- The detail card no longer truncates itself at Small or sit half empty at Large.

## 1.0.0

- The first release. A floating rail of rings against the edge of the screen, one per coding agent, showing how much of each limit is left.
