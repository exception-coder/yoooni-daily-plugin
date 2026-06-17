# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## What this repo is

This is the **source repo of a Claude Code plugin** (`yoooni-daily-plugin`). It is NOT a business application — it produces a plugin installed via `/plugin marketplace add … && /plugin install yoooni-daily-plugin@yoooni-daily-plugin`.

The plugin ships **Skills** under `skills/*/SKILL.md` — natural-language-triggered playbooks (Claude routes by the `description:` frontmatter, no slash command needed).

It also ships a **SessionStart hook** (`hooks/hooks.json` + `hooks/session-autoupdate.js`) + **PowerShell scripts** (`scripts/`) that auto-maintain the company suite: 每日后台 `git pull` + 重建公司 MCP 仓（project-domain-knowledge / cross-project-topology），并把插件新版提示带进上下文；`scripts/register-autoupdate-task.ps1` 注册 Windows 计划任务（schtasks、每 4 小时）。详见 `skills/yoooni-update-team-tools`。开关 `YOOONI_AUTOUPDATE=off|now`。`.ps1` 须带 UTF-8 BOM（见下）。

## Plugin manifest layout

- [.claude-plugin/plugin.json](.claude-plugin/plugin.json) — installable plugin manifest.
- [.claude-plugin/marketplace.json](.claude-plugin/marketplace.json) — marketplace entry pointing at this repo.

**Version bumping requires editing BOTH files** — `version` and `description` must stay in lockstep. Self-check:

```powershell
$v1 = (Get-Content .claude-plugin\plugin.json | ConvertFrom-Json).version
$v2 = (Get-Content .claude-plugin\marketplace.json | ConvertFrom-Json).plugins[0].version
if ($v1 -ne $v2) { Write-Error "version mismatch: plugin.json=$v1 marketplace.json=$v2" }
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
