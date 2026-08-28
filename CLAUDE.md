# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this repo is

This is the **source repo of a Claude Code plugin** (`yoooni-daily-plugin`). It is NOT a business application — it produces a plugin installed via `/plugin marketplace add … && /plugin install yoooni-daily-plugin@yoooni-daily-plugin`.

The plugin ships **Skills** under `skills/*/SKILL.md` — natural-language-triggered playbooks (Claude routes by the `description:` frontmatter, no slash command needed).

It also ships a **read-only plugin-version reminder hook** (`hooks/hooks.json`) + repository maintenance scripts (`scripts/`). Installation and updates are scripts, not Skills. The plugin does not update plugins or MCP servers on `SessionStart`, and bootstrap installation does not register a schedule by default. Users explicitly run `scripts/update-team-tools.*`; `scripts/register-autoupdate-task.*` remains opt-in. An existing optional task is only self-healed with `-OnlyIfExists`, never created implicitly. 提示词信号上传另需显式 `YOOONI_PROMPT_SIGNAL_UPLOAD=on`。`.ps1` 须带 UTF-8 BOM（见下）。

> 历史背景：`claude plugin` 早期不是 CLI 子命令，插件只能在会话里走 `/plugin` slash；现已是完整 CLI（`install/update/marketplace`），脚本可全自动代劳——旧文档中"插件更新需手敲 slash / 脚本代不了"的说法已废弃。插件名在 CLI 中须带 `@marketplace` 全限定（裸名报 `not found`）。

## Plugin manifest layout

> 子目录布局（与 team-standards 一致）：仓库根只放两份 **marketplace** 清单，**插件本体**在 `plugins/yoooni-daily-plugin/`。codex 要求插件在子目录、不认根布局 `source:"./"`。

- [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json) — Claude marketplace 入口（`source` 指向 `./plugins/yoooni-daily-plugin`）。
- [.agents/plugins/marketplace.json](.agents/plugins/marketplace.json) — Codex marketplace 清单（OpenAI 格式，`source.path` 同指子目录；缺它/或用根布局 codex `plugin add` 会 `plugin not found`）。`.agents` 清单**不带 version**，无需随版本改。
- `plugins/yoooni-daily-plugin/.claude-plugin/plugin.json` — Claude 可安装插件清单。
- `plugins/yoooni-daily-plugin/.codex-plugin/plugin.json` — Codex 插件清单（含 `interface` 富描述）。
- 插件内容（skills / hooks / scripts）均在 `plugins/yoooni-daily-plugin/` 下。

**Version bumping requires editing 3 files** — `plugins/yoooni-daily-plugin/.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`、`plugins/yoooni-daily-plugin/.codex-plugin/plugin.json` 的 `version` 必须 lockstep（`description` 也尽量同步）。Self-check:

```powershell
$v1 = (Get-Content plugins\yoooni-daily-plugin\.claude-plugin\plugin.json | ConvertFrom-Json).version
$v2 = (Get-Content .claude-plugin\marketplace.json | ConvertFrom-Json).plugins[0].version
$v3 = (Get-Content plugins\yoooni-daily-plugin\.codex-plugin\plugin.json | ConvertFrom-Json).version
if (($v1 -ne $v2) -or ($v1 -ne $v3)) { Write-Error "version mismatch: claude plugin=$v1 marketplace=$v2 codex=$v3" }
```

> ⚠️ **JSON 必须是无 BOM 的 UTF-8**。PowerShell 5.1 的 `Set-Content -Encoding UTF8` / `Out-File -Encoding UTF8` 会写入 **BOM**，导致 `/plugin marketplace add` 报 `Invalid JSON ... Unrecognized token`。改 json 用无 BOM 方式：
> ```powershell
> [System.IO.File]::WriteAllText($f, $text, (New-Object System.Text.UTF8Encoding($false)))
> ```
> 自检 BOM：`([System.IO.File]::ReadAllBytes($f)[0..2] -join ',') -eq '239,187,191'` 应为 `False`。
> （`.ps1` 脚本则相反：PS 5.1 需要 **带 BOM** 的 UTF-8 才能正确读中文。）

## Adding a new skill

1. Create `skills/<name>/SKILL.md` with frontmatter:
   ```yaml
   ---
   name: <name>
   description: <triggers + purpose — must let the LLM judge when to invoke>
   ---
   ```
2. Bump version in **both** `plugin.json` and `marketplace.json`.
3. Update `README.md` 中的 Skill 计数、清单和边界说明：

公共 Skill 必须是 Yoooni 日常协作的稳定用户意图；项目专属能力和仓库维护脚本不得新增为 Skill。

## Version bump convention

| 改动类型 | 版本号增量 |
|---|---|
| README / CLAUDE / 注释 only | patch (+0.0.1) |
| skill 内容修订 / bugfix | patch (+0.0.1) |
| 新增 skill | minor (+0.1.0) |
| 破坏性变更 | major (+1.0.0) |

## Style notes

- Comments and skill docs are **Chinese-first**.
- Main branch: commit directly to `master` and push (individual-maintained release branch, no PR needed).
- Commit style: `feat/fix/refactor/docs(scope): 标题`，body 中文说明。
