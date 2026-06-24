---
name: yoooni-hook-report
description: 出一份「hook 命中周报」——统计团队 warn 档 hook 的命中情况，用数据决定某条规则要不要从 warn 升 block、看大家最常踩哪条规范。当用户说"hook 命中周报"、"hook 命中统计"、"规则命中排行"、"大家踩了哪些规范"、"哪条规则该升 block"、"warn 统计"、"看看 vibecoding 日志"时触发。数据来自公司共享 \\IT01\版本更新\vibecoding 下各人上报的 hook-events-*.jsonl（由 team-standards / project-coding-profiles 的 warn hook 本地登记、update-team-tools.ps1 best-effort 同步）。需能访问 \\IT01 共享。
---

# hook 命中周报

把团队各人的 hook 命中事件聚合成统计，回答两个问题：

1. **某条规则要不要从 warn 升 block** —— 看它命中频率、warn/block 占比。
2. **大家最常踩哪条规范、谁常踩** —— 规则命中排行 + 按用户。

## 数据从哪来（闭环）

```
warn hook 命中(team-standards / project-coding-profiles)
   → 本地 ~/.kai-toolbox/hook-events.jsonl   (hooks/event-log.js，best-effort、只写本地)
   → update-team-tools.ps1 同步(计划任务/SessionStart)
   → \\IT01\版本更新\vibecoding\hook-events-<用户>-<机器>.jsonl   (每人一文件)
   → 本 skill 读整个目录聚合
```

事件字段：`ts / user / host / plugin / hook / rule / mode(warn|block) / tool / file`。

## 怎么跑

```powershell
# 默认读 \\IT01\版本更新\vibecoding，统计最近 7 天
node "<plugin>\skills\yoooni-hook-report\hook-report.mjs"

# 指定天数 / 全部 / 原始 JSON / 换数据目录
node hook-report.mjs --days=30
node hook-report.mjs --days=0          # 全部
node hook-report.mjs --json            # 原始聚合 JSON
node hook-report.mjs "D:\some\dir"     # 换共享/本地目录（排查用）
```

输出五张表：**规则命中 Top**、**谁命中最多**、**warn vs block**、**按 hook**、**按插件**。

## 前提与边界

- 需能访问 `\\IT01\版本更新\vibecoding`。访问不了先跑 `yoooni-smb-share-access` 修 SMB。
- 只读不写，纯聚合统计。
- 数据是 best-effort 上报：同事电脑没开 Claude Code / 没跑同步时，其数据会滞后——趋势参考，不必苛求实时精确。
- 解读建议：某规则**命中量大且集中在少数文件/少数人**→ 多为真实高频痛点，可考虑升 block；**命中量大但分散且多为一次性**→ 可能误报偏多，先优化判定再说。

## 怎么把某条规则升 block

确认要升级后，让对应 hook 默认 block（环境变量，或改 hook 默认值由插件维护者发版）：

| 规则 | 环境变量 |
|---|---|
| sql-ddl | `TEAM_STANDARDS_SQL_DDL_HOOK=block` |
| backend-kg | `TEAM_STANDARDS_BACKEND_KG_HOOK=block` |
| file-encoding | `PCP_ENCODING_HOOK=block` |
| frontend-controls | `PCP_FRONTEND_HOOK=block` |
