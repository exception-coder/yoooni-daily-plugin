---
name: yoooni-update-team-tools
description: 更新/同步公司团队套件（插件 + MCP），以及开启/管理自动更新。当用户说"更新公司套件 / 更新团队工具 / 刷新插件和MCP / 同步最新规范 / 团队工具有没有新版 / 开启自动更新 / 装个定时自动更新 / 关掉自动更新 / update team tools"时触发。也是 SessionStart 自动更新（每日后台 git pull + 重建 MCP 仓 + 自动更新插件）的手动入口与开关说明。MCP 仓与插件（team-standards / project-coding-profiles / yoooni-daily-plugin）现均可全自动同步——插件走 `claude plugin` CLI（marketplace update + plugin update），脚本/计划任务可代劳，无需手敲 slash；插件更新后重启会话生效。
---

# 更新公司团队套件（AI 自动维护）

## 先讲清楚：能自动到什么程度

| 层 | 内容 | 自动程度 |
|---|---|---|
| **MCP 仓**（project-domain-knowledge 引擎 / cross-project-topology 知识） | 业务知识、DDL、引擎代码 | ✅ **全自动**：SessionStart hook 每日后台 + Windows 计划任务，都会 `git pull` → 引擎有变化才 rebuild → 幂等重注册。MCP 跑本地文件，更新即生效 |
| **插件**（team-standards / project-coding-profiles / yoooni-daily-plugin） | skill / hook 规则 | ✅ **全自动**：脚本走 `claude plugin marketplace update` 刷源 → `claude plugin update <plugin>@<marketplace>` 逐个更新（幂等，已最新则空跑）。**更新后重启会话生效**，notice 会提示 |

> 一句话：装一个 `yoooni-daily-plugin` 后，**MCP 与插件都零操作保持最新**；插件更新落地需重启一次会话。
>
> 背景：`claude plugin` 现已是完整 CLI（`install / update / marketplace …`），所以"插件只能在会话里跑 slash、脚本代不了"的旧限制**已不再适用**——本 skill 与脚本均已升级为全自动。

## A. 立即全量同步一次

```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\scripts\update-team-tools.ps1"
```

它会两段都跑完：
1. **MCP**：pull 两个 MCP 仓 → 引擎有变化才 `npm install/build` → 幂等重注册 `domain-knowledge` / `cross-topology`。
2. **插件**：`claude plugin marketplace update` 刷源 → 对 `team-standards` / `project-coding-profiles` / `yoooni-daily-plugin` 逐个 `claude plugin update <p>@<p>`（幂等）。有更新就写 notice「已更新到 vX，重启会话生效」。

- 仓库目录**自动定位**（无需传路径）：参数 → 环境变量 `YOOONI_WORKSPACE_DIR` → 配置 `%USERPROFILE%\.kai-toolbox\workspace.path` → 从 `claude mcp get domain-knowledge` 解析 → 默认 `%USERPROFILE%\myWork`。（插件更新不依赖此目录，直接走已注册 marketplace。）
- 日志：`%USERPROFILE%\.kai-toolbox\team-tools-update.log`。

> 想手动只更新插件、不碰 MCP，也可直接：
> ```powershell
> claude plugin marketplace update
> claude plugin update team-standards@team-standards -s user
> claude plugin update project-coding-profiles@project-coding-profiles -s user
> ```
> 注意：插件名必须带 `@marketplace` 全限定（裸名会报 `not found`）；更新后**重启会话**才加载新版。

## B. 开启"会话外也定时刷新"（Windows 计划任务）

登录时 + 每 4 小时自动跑同步脚本（即使没开 Claude Code），用户级任务、无需管理员：

```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\scripts\register-autoupdate-task.ps1"
# 仓库在 D 盘等非默认位置时指定： -WorkspaceDir D:\Users\zhang\myWork
```

- 查看：`Get-ScheduledTask -TaskName YoooniTeamToolsAutoUpdate`
- 卸载：`Unregister-ScheduledTask -TaskName YoooniTeamToolsAutoUpdate -Confirm:$false`

## C. 自动更新开关（SessionStart hook，默认已开）

每次开 Claude Code 会话，`hooks/session-autoupdate.js` 会：每天最多一次在后台刷新 MCP 仓 + 自动更新插件（不阻塞会话），并把"插件已更新、重启会话生效"提示带进上下文。

| 想要 | 设环境变量 |
|---|---|
| 关闭自动更新 | `YOOONI_AUTOUPDATE=off` |
| 下次开会话立即刷一次 | `YOOONI_AUTOUPDATE=now` |
| 默认（每日一次） | 不设 / `=on` |

## 边界（诚实说明）

- 插件 `update` 走 `claude plugin` CLI，脚本/计划任务可全自动代劳；唯一不能省的是**更新后重启会话**才会加载新版（CLI 自身也提示 `Restart to apply`）。
- 插件名在 CLI 里必须带 `@marketplace` 全限定（如 `team-standards@team-standards`），裸名会 `not found`。
- 首次安装本插件那一步仍建议在会话里 `/plugin marketplace add` + `/plugin install`（或用 `yoooni-install-team-tools` skill 一键引导）；装好后，后续更新即全自动。
- `<plugin>` 为本插件安装路径（不确定就用脚本绝对路径）。
