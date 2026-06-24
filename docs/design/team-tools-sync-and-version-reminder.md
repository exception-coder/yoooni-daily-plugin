# 设计：团队套件同步与版本陈旧提醒（yoooni-daily-plugin 侧）

> 与 team-standards 的 `docs/design/prompt-signal-capture.md` 配套。team-standards
> 只负责「在本地产生信号」，本插件负责「同步到公司内网 \\IT01」与「提醒重启会话」。

## 背景

Claude Code 在【会话启动那一刻】把 plugins/hooks/skills 一次性加载进内存，运行中
不热加载。`update-team-tools.ps1`（每日刷新 / 计划任务 / 手动）把新版插件与 MCP 仓
拉到磁盘，但同事若一直泡在老会话里不重启，这个会话就一直跑旧版——新规范、新脚本、
新 hook 全都不生效。

## 本插件承担的两件事

### 1. 同步本地信号到 \\IT01（update-team-tools.ps1）

- `hook-events.jsonl`：team-standards / project-coding-profiles 的 warn hook 命中事件。
- `prompt-signals-<用户>-<机器>.jsonl`：team-standards 的 `prompt-signal-capture`
  (UserPromptSubmit) hook 采集的团队疑问/纠正信号。

同步红线（与 hook-event-logging 同源）：

- **best-effort**：共享 `\\IT01\版本更新\vibecoding` 不可达即跳过，全程 try/catch，
  绝不影响刷新主流程。
- **每人一文件、整文件覆盖**：本地文件名已含 `<用户>-<机器>`，覆盖拷贝即幂等，
  根除跨机并发写冲突。
- **上行默认开**：`YOOONI_PROMPT_SIGNAL_UPLOAD=off` 时只留本地、不推共享。

### 2. 版本陈旧提醒（hooks/check-plugin-version-stale.js）

UserPromptSubmit hook，每条 prompt 提交时比对：

- 已加载版本：当前会话运行的 `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
- 磁盘最新版本：marketplace 克隆的 `.claude-plugin/marketplace.json`

磁盘 semver 更高即 stderr 提醒「插件已更新，请重启会话」。

最佳实践（各自检测 + 共享去重）：

- 「已加载版本」只能靠各插件自己的 `CLAUDE_PLUGIN_ROOT` 拿到、跨插件拿不到，故
  team-standards / project-coding-profiles / yoooni-daily-plugin **各放一份本 hook
  只判自己**。
- 三个插件同日一起更新时不刷三条：用会话级共享 flag
  `~/.kai-toolbox/.restart-reminded-<session>` 以 `'wx'` 原子抢占，谁先抢到谁提醒
  一次，其余静默——反正重启一次三个插件全更新。

红线：best-effort、绝不写 stdout（UserPromptSubmit 的 stdout 会注入 prompt）、
绝不阻断、永远 exit 0。旁路 `YOOONI_VERSION_REMINDER=off`。

已知局限（鸡生蛋）：本 hook 自身也要会话重启后才生效，故只对「装上本 hook 之后的
版本更新」起作用——越早铺开越省心。

## 边界

- team-standards：只产生本地信号，不感知 \\IT01。
- 本插件：承接 \\IT01 同步 + 各自的版本陈旧提醒。
- 聚合（读 \\IT01 出周报、产候选）：另行实现，人审才成规。
