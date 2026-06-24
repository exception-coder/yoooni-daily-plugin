# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this repo is

This is the **source repo of a Claude Code plugin** (`yoooni-daily-plugin`). It is NOT a business application — it produces a plugin installed via `/plugin marketplace add … && /plugin install yoooni-daily-plugin@yoooni-daily-plugin`.

The plugin ships **Skills** under `skills/*/SKILL.md` — natural-language-triggered playbooks (Claude routes by the `description:` frontmatter, no slash command needed).

It also ships a **SessionStart hook** (`hooks/hooks.json` + `hooks/session-autoupdate.js`) + **PowerShell scripts** (`scripts/`) that auto-maintain the company suite: 每日后台 `git pull` + 重建公司 MCP 仓（project-domain-knowledge / cross-project-topology），**并通过 `claude plugin` CLI 全自动更新插件**（`claude plugin marketplace update` + `claude plugin update <p>@<p>`，覆盖 team-standards / project-coding-profiles / yoooni-daily-plugin，幂等，更新后重启会话生效）；`scripts/register-autoupdate-task.ps1` 注册 Windows 计划任务（schtasks、每 4 小时），任务指向**固定路径稳定启动器** `scripts/run-update.ps1`（部署到 `%USERPROFILE%\.kai-toolbox\run-update.ps1`，运行时再定位缓存里最新版本的 `update-team-tools.ps1`）——避免本插件自更新后版本化缓存目录失效导致任务断链；`update-team-tools.ps1` 跑完会以 `-OnlyIfExists` 自愈校准任务。详见 `skills/yoooni-update-team-tools`。开关 `YOOONI_AUTOUPDATE=off|now`。`.ps1` 须带 UTF-8 BOM（见下）。

> 历史背景：`claude plugin` 早期不是 CLI 子命令，插件只能在会话里走 `/plugin` slash；现已是完整 CLI（`install/update/marketplace`），脚本可全自动代劳——旧文档中"插件更新需手敲 slash / 脚本代不了"的说法已废弃。插件名在 CLI 中须带 `@marketplace` 全限定（裸名报 `not found`）。

## Plugin manifest layout

- [.claude-plugin/plugin.json](.claude-plugin/plugin.json) — Claude 可安装插件清单。
- [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json) — Claude marketplace 入口（指向本仓）。
- [.codex-plugin/plugin.json](.codex-plugin/plugin.json) — Codex 插件清单（含 `interface` 富描述）。
- [.agents/plugins/marketplace.json](.agents/plugins/marketplace.json) — Codex marketplace 清单（OpenAI 格式，缺它 codex `plugin add` 会 `plugin not found`）。`.agents` 清单**不带 version**，无需随版本改。

**Version bumping requires editing 3 files** — `.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`、`.codex-plugin/plugin.json` 的 `version` 必须 lockstep（`description` 也尽量同步）。Self-check:

```powershell
$v1 = (Get-Content .claude-plugin\plugin.json | ConvertFrom-Json).version
$v2 = (Get-Content .claude-plugin\marketplace.json | ConvertFrom-Json).plugins[0].version
$v3 = (Get-Content .codex-plugin\plugin.json | ConvertFrom-Json).version
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
3. Update `README.md` in **4 places**:

| README.md 位置 | 操作 |
|---|---|
| 顶部 "包含 **N 个 Skill**" 计数 | `+1` |
| 顶部 skill 表格 | 追加一行 |
| "Skills 一览" 章节 | 追加详细段 |
| "目录结构" 章节 | 追加目录条目 |

自检：`Select-String -Pattern '<skill-name>' README.md | Measure-Object | Select -ExpandProperty Count` ≥ 4

## Version bump convention

| 改动类型 | 版本号增量 |
|---|---|
| README / CLAUDE / 注释 only | patch (+0.0.1) |
| skill 内容修订 / bugfix | patch (+0.0.1) |
| 新增 skill | minor (+0.1.0) |
| 破坏性变更 | major (+1.0.0) |

## Style notes

- Comments and skill docs are **Chinese-first**.
- Main branch: commit directly to `main` and push (individual-maintained release branch, no PR needed).
- Commit style: `feat/fix/refactor/docs(scope): 标题`，body 中文说明。
