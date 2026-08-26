---
name: yoooni-update-team-tools
description: 用于更新或同步公司插件与 MCP，以及开启、关闭或检查定时自动更新。用户要求刷新团队工具或最新规范时使用。
---

# 更新公司团队套件（默认手动触发）

## 先讲清楚：能自动到什么程度

| 层 | 内容 | 自动程度 |
|---|---|---|
| **MCP 仓**（project-domain-knowledge 引擎 / cross-project-topology 知识） | 业务知识、DDL、引擎代码 | ✅ **手动命令内自动完成**：用户触发后执行 `git pull` → 引擎有变化才 rebuild → 幂等重注册。MCP 跑本地文件，更新即生效 |
| **插件**（team-standards / project-coding-profiles / yoooni-daily-plugin） | skill / hook 规则 | ✅ **手动命令内自动完成**：用户触发后脚本走 `claude plugin marketplace update` 刷源 → `claude plugin update <plugin>@<marketplace>` 逐个更新（幂等，已最新则空跑）。**更新后重启会话生效**，notice 会提示 |

> 一句话：默认不会后台更新；用户明确说“更新公司套件”后，脚本一次完成 MCP 与插件同步。插件更新落地需重启一次会话。
>
> 背景：`claude plugin` 现已是完整 CLI（`install / update / marketplace …`），所以"插件只能在会话里跑 slash、脚本代不了"的旧限制**已不再适用**——本 skill 与脚本均已升级为全自动。

## A. 立即全量同步一次

```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\scripts\update-team-tools.ps1"
```

> **macOS / Linux**：用同名 `.sh`（逻辑、状态文件 `~/.kai-toolbox/*`、Gitee 源完全一致）：
> ```bash
> bash "<plugin>/scripts/update-team-tools.sh"
> ```

它会两段都跑完：
1. **MCP**：pull 两个 MCP 仓 → 引擎有变化时，有 `package-lock.json` 走可复现的 `npm ci`，否则回退 `npm install`，随后 build → 幂等重注册 `domain-knowledge` / `cross-topology`。
2. **插件**：`claude plugin marketplace update` 刷源 → 对 `team-standards` / `project-coding-profiles` / `yoooni-daily-plugin` 逐个 `claude plugin update <p>@<p>`（幂等）。有更新就写 notice「已更新到 vX，重启会话生效」。

并发控制使用可独立测试的锁组件：Windows 命名 Mutex 能恢复进程异常退出留下的 abandoned 状态；macOS/Linux PID 锁只接受大于 1 的纯数字活动 PID，陈旧或非法 PID 安全恢复，避免对进程组执行误判探测。

- 仓库目录**自动定位**（无需传路径）：参数 → 环境变量 `YOOONI_WORKSPACE_DIR` → 配置 `%USERPROFILE%\.kai-toolbox\workspace.path` → 从 `claude mcp get domain-knowledge` 解析 → 默认 `%USERPROFILE%\myWork`。（插件更新不依赖此目录，直接走已注册 marketplace。）
- 日志：`%USERPROFILE%\.kai-toolbox\team-tools-update.log`。
- 提示词信号默认只留本地；只有显式设置 `YOOONI_PROMPT_SIGNAL_UPLOAD=on` 时，才把已脱敏的 `prompt-signals-*.jsonl` 同步到团队共享。

> 想手动只更新插件、不碰 MCP，也可直接：
> ```powershell
> claude plugin marketplace update
> claude plugin update team-standards@team-standards -s user
> claude plugin update project-coding-profiles@project-coding-profiles -s user
> ```
> 注意：插件名必须带 `@marketplace` 全限定（裸名会报 `not found`）；更新后**重启会话**才加载新版。

## B. 可选：显式开启定时刷新（计划任务）

默认不创建任何计划任务。只有用户明确要求后台自动更新时，才运行下列注册命令；用户级任务无需管理员：

**Windows（计划任务 schtasks）**
```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\scripts\register-autoupdate-task.ps1"
```
- 查看：`Get-ScheduledTask -TaskName YoooniTeamToolsAutoUpdate`
- 卸载：`Unregister-ScheduledTask -TaskName YoooniTeamToolsAutoUpdate -Confirm:$false`

**macOS（launchd）**
```bash
bash "<plugin>/scripts/register-autoupdate-task.sh" --every-hours 4
```
- 查看：`launchctl list | grep com.yoooni.team-tools-autoupdate`
- 卸载：`launchctl unload ~/Library/LaunchAgents/com.yoooni.team-tools-autoupdate.plist && rm ~/Library/LaunchAgents/com.yoooni.team-tools-autoupdate.plist`
- **Linux**：无 launchd，请用 cron：`crontab -e` 加 `0 */4 * * * ~/.kai-toolbox/run-update.sh`

> **稳定启动器（防自更新断链）**：计划任务**不直接**指向版本化的 `update-team-tools.ps1`，而是指向固定路径的启动器 `%USERPROFILE%\.kai-toolbox\run-update.ps1`；启动器运行时再定位缓存里**最新版本**的脚本来跑。
> 原因：`claude plugin` 缓存目录带版本号，本插件**自更新**后旧版本目录会被回收——若任务写死旧路径就会断掉。
> **自愈**：`update-team-tools.ps1` 每次跑完都会校准计划任务（`register-autoupdate-task.ps1 -OnlyIfExists`，仅当任务已存在）；旧版本注册的"直指 update 脚本"的任务，会在下次刷新时被自动迁移到启动器。从没注册过计划任务的机器不受影响、也不会被擅自创建。

## C. 默认行为：不自动更新

- 不注册 `SessionStart` 自动更新 Hook。
- 一键安装脚本默认不创建 Windows 计划任务或 macOS launchd 任务。
- `YOOONI_AUTOUPDATE` 开关已停用；需要更新时运行 A 节命令。
- 版本提醒 Hook 只比较版本并提示，不修改插件、MCP 或配置。

## 边界（诚实说明）

- 插件 `update` 走 `claude plugin` CLI，用户手动触发脚本后可完成整套更新；唯一不能省的是**更新后重启会话**才会加载新版（CLI 自身也提示 `Restart to apply`）。
- 插件名在 CLI 里必须带 `@marketplace` 全限定（如 `team-standards@team-standards`），裸名会 `not found`。
- 首次安装本插件那一步仍建议在会话里 `/plugin marketplace add` + `/plugin install`（或用 `yoooni-install-team-tools` skill 一键引导）；装好后，后续更新由用户明确触发。
- `<plugin>` 为本插件安装路径（不确定就用脚本绝对路径）。
