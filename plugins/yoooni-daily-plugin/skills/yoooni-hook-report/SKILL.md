---
name: yoooni-hook-report
description: 生成团队 vibecoding 周报。用户要求 hook 命中排行、warn 升级分析、疑问纠正归纳或 prompt 信号统计时使用；数据来自 IT01 共享。
---

# 团队 vibecoding 周报

两部分：**① hook 命中统计**（规则该不该升 block）+ **② 疑问/纠正规整**（业务缺口 → 该补什么）。
默认两部分都出；用户只问其一时只跑对应那部分。

## ① hook 命中统计

把团队各人的 hook 命中事件聚合成统计，回答两个问题：

1. **某条规则要不要从 warn 升 block** —— 看它命中频率、warn/block 占比。
2. **大家最常踩哪条规范、谁常踩** —— 规则命中排行 + 按用户。

## 数据从哪来（闭环）

```
warn hook 命中(team-standards / project-coding-profiles)
   → 本地 ~/.kai-toolbox/hook-events.jsonl   (hooks/event-log.js，best-effort、只写本地)
   → update-team-tools.ps1 同步(人工运行或显式启用的计划任务)
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

## ② 疑问/纠正规整（业务缺口 → 该补什么）

把同事**对 AI 的疑问/纠正**（反复问的业务、反复纠偏的点）归纳成"该补什么"。数据来自 `prompt-signals-*.jsonl`（`prompt-signal-capture` hook 已在采集层降噪/去重/标 priority）。

**第 1 步：备料（机械）** —— 跑脚本拿去噪去重后、按 priority 排好的高价值条目：
```powershell
node "<plugin>\skills\yoooni-hook-report\prompt-signal-report.mjs"            # 最近 7 天
node prompt-signal-report.mjs --days=30 --top=80     # 调范围/条数
node prompt-signal-report.mjs --json                 # 给程序用
```
它输出：按类型/优先级/项目的计数 + 高价值条目列表（`priority|kind|afterEdit (项目/人/日期) 原文摘要`）。`priority` 序：`high+`(纠正且紧跟编辑) > `high`(纠正) > `medium`(疑问) > `low`(任务/其它)。

**第 2 步：规整（LLM，本 skill 的核心）** —— 读上面输出，**你（AI）**做归纳，**不要**只复述原文：
1. **聚类**：把指向同一主题的条目合并（如多条都在问"配送/收胚取哪个字段" → 一簇）。
2. 每簇产出一行：
   | 业务领域/主题 | 类型(疑问/纠正) | 命中频次·涉及人 | 推断的缺口 | 建议补到哪 |
   - **建议补到哪**按缺口性质分流：
     - 业务字段/口径/流程不清 → **domain-knowledge 知识库** 或 **glossary 术语表**（`_candidates.md`）
     - 反复纠正同类编码写法 → **team-standards 通用规范/skill**（够客观可加 hook）
     - 项目专属约定 → **project-coding-profiles** 对应项目画像
     - AI 老理解错某类意图 → 优化相关 **skill 的 description/提示词**
3. **排序**：先列 `high+`/`high`（纠正，最该立即处理）、再 `medium`（疑问，知识盲区）。
4. **红线**：产出的是**候选**，不是规——"要不要真补、补成什么"由人点头（与 hook 命中→升 block 一致）。

> 为什么规整放这里、不放 hook：采集层(正则)读不懂"这是什么业务问题"，只能去明显噪声；**精准提取业务缺口是语义活，必须 LLM 过一遍**——这一步就是那道 LLM 规整。

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
