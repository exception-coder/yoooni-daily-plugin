---
name: yoooni-update-team-tools
description: 更新/同步公司团队套件（插件 + MCP），以及开启/管理自动更新。当用户说"更新公司套件 / 更新团队工具 / 刷新插件和MCP / 同步最新规范 / 团队工具有没有新版 / 开启自动更新 / 装个定时自动更新 / 关掉自动更新 / update team tools"时触发。也是 SessionStart 自动更新（每日后台 git pull + 重建 MCP 仓）的手动入口与开关说明。MCP 仓可全自动同步；插件（team-standards / project-coding-profiles）更新需在会话里跑 /plugin slash（脚本代不了），本 skill 会一键完成 MCP 同步并打印插件 slash 命令。
---

# 更新公司团队套件（AI 自动维护）

## 先讲清楚：能自动到什么程度

| 层 | 内容 | 自动程度 |
|---|---|---|
| **MCP 仓**（project-domain-knowledge 引擎 / cross-project-topology 知识） | 业务知识、DDL、引擎代码 | ✅ **全自动**：SessionStart hook 每日后台 + Windows 计划任务，都会 `git pull` → 引擎有变化才 rebuild → 幂等重注册。MCP 跑本地文件，更新即生效，**无需 slash** |
| **插件**（team-standards / project-coding-profiles） | skill / hook 规则 | ⚠️ **半自动**：装/更新走 `/plugin` **slash 命令**，任何脚本/hook 都代不了；本 skill 检测到新版会提示并打印命令，**你点一下** |

> 一句话：装一个 `yoooni-daily-plugin` 后，**MCP 那半零操作保持最新；插件那半"自动检测 + 一键提示"**。

## A. 立即全量同步一次

```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\scripts\update-team-tools.ps1"
```

它会：pull 两个 MCP 仓 → 引擎有变化才 `npm install/build` → 幂等重注册 `domain-knowledge` / `cross-topology`。
- 仓库目录**自动定位**（无需传路径）：参数 → 环境变量 `YOOONI_WORKSPACE_DIR` → 配置 `%USERPROFILE%\.kai-toolbox\workspace.path` → 从 `claude mcp get domain-knowledge` 解析 → 默认 `%USERPROFILE%\myWork`。
- 日志：`%USERPROFILE%\.kai-toolbox\team-tools-update.log`。

若脚本/上下文提示"插件有新版"，在 **Claude Code 会话**里执行（slash，脚本代不了）：

```
/plugin marketplace update
/plugin install team-standards@team-standards
/plugin install project-coding-profiles@project-coding-profiles
/reload-plugins
```

## B. 开启"会话外也定时刷新"（Windows 计划任务）

登录时 + 每 4 小时自动跑同步脚本（即使没开 Claude Code），用户级任务、无需管理员：

```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\scripts\register-autoupdate-task.ps1"
# 仓库在 D 盘等非默认位置时指定： -WorkspaceDir D:\Users\zhang\myWork
```

- 查看：`Get-ScheduledTask -TaskName YoooniTeamToolsAutoUpdate`
- 卸载：`Unregister-ScheduledTask -TaskName YoooniTeamToolsAutoUpdate -Confirm:$false`

## C. 自动更新开关（SessionStart hook，默认已开）

每次开 Claude Code 会话，`hooks/session-autoupdate.js` 会：每天最多一次在后台刷新 MCP 仓（不阻塞会话），并把"插件有新版"提示带进上下文。

| 想要 | 设环境变量 |
|---|---|
| 关闭自动更新 | `YOOONI_AUTOUPDATE=off` |
| 下次开会话立即刷一次 | `YOOONI_AUTOUPDATE=now` |
| 默认（每日一次） | 不设 / `=on` |

## 边界（诚实说明）

- 插件 `install`/`update` 是 **slash 命令**，任何脚本、hook、计划任务都**代不了**——这是 Claude Code 的机制，不是我们能绕的。本 skill 已把它收敛成"自动检测 + 一键打印命令"。
- 首次安装本插件（一次 `/plugin marketplace add` + `/plugin install`）仍需手动；装好后，MCP 自动维护、插件半自动维护即生效。
- `<plugin>` 为本插件安装路径（不确定就用脚本绝对路径）。
