---
name: yoooni-onboard-pipeline
description: 用于新代码项目或新系统一键 onboarding：定位仓库与系统边界，生成 Agent 入口和编码画像，运行 Graphify，初始化领域知识与 DDL，起草全模块 Core Spec，接入运行证据挖掘，并登记跨项目拓扑与完成验证。用户要求“初始化新项目”“一键 onboard”“接入新系统”“生成项目业务图谱/Graphify/Core Spec 全套基线”时使用；不用于新同事入职、SVN 公司文档拉取或个人开发环境搭建，那些由 yoooni-onboard-init 负责。
---

# 新项目初始化流水线 Skill

把“接入一个新代码项目”的全套作业编排成一条流水线：**项目边界 → Agent 入口 → 编码 profile → 多仓聚合 → Graphify → 领域知识/DDL → Core Spec → 运行证据 → 跨项目拓扑 → 验证发布**。

**定位**:编排器,不是黑盒。机械步骤(clone/聚合/建骨架)自动跑;需判断的节点(模块切分、技术栈、stable 与否、集成关系)停下来让人/AI 决策。复用已有能力,不重造。

## 快速导航

- **确认适用范围** → [触发条件](#触发条件) / [红线](#红线)
- **查看 CLI 和状态** → [编排脚本](#编排脚本机械胶水)
- **执行完整初始化** → [十阶段执行流程](#十阶段执行流程)
- **核对复用边界** → [与下层能力的关系](#与下层能力的关系不重造)

## 触发条件

- "初始化新项目" / "一键 onboard" / "接入一个新系统"
- "把某项目拉起来,建知识图谱和编码规范"
- "项目初始化流水线" / "工作台初始化作业"

## 红线

- ❌ 不无人值守全自动入库——业务真理走人工关卡,产出经评审才升 stable(见 domain-knowledge-bootstrap)。
- ❌ 不在本流水线重写知识抽取/profile 逻辑——一律调用下层已有 skill。
- ❌ 不把静态扫描结果当作已验证 Core Spec；无运行证据时必须显式保留 `waiting-evidence`。
- ❌ 不承接新同事入职、SVN 文档 checkout 或 IDEA 环境搭建；交给 `yoooni-onboard-init` 链路。
- ✅ 幂等可续跑:每阶段状态记在 `~/.kai-toolbox/onboard-<系统>.json`,中断后可接着跑。
- ✅ 兼容旧六阶段状态文件：保留原阶段 ID 与既有 `status/at`，自动补齐新增阶段。

## 前置

- 在能访问目标项目代码的机器上；需能访问 Graphify、`project-domain-knowledge`、
  `project-coding-profiles` 与 `cross-project-topology`（团队工具已装，见 `yoooni-install-team-tools`）。
- 本 skill 自带编排脚本:`<plugin>/skills/yoooni-onboard-pipeline/pipeline.mjs`。

## 编排脚本(机械胶水)

```
node pipeline.mjs plan --repos <路径或url>... [--name <系统>] [--ws <工作区父目录>]
   探测每个仓角色(前端/后端/微服务)、判前后端分离、产出十阶段计划 + 状态文件
node pipeline.mjs mark --name <系统> --stage <id> \
  [--status pending|needs-review|waiting-evidence|done|skipped]
   标记某阶段完成(每过一道关卡就 mark)
node pipeline.mjs aggregate --name <系统> --members <路径>...
   调 yoooni-taskspace 建前后端聚合工作区
node pipeline.mjs status --name <系统>
   看进度
```

阶段 id：`fetch / profile / coding / aggregate / graphify / knowledge / core-spec / evidence / topology / verify`。

状态含义：

- `pending`：尚未开始。
- `needs-review`：候选已生成，等待 owner 评审。
- `waiting-evidence`：采集入口已准备，但暂无足够运行证据。
- `done`：通过本阶段门禁。
- `skipped`：仅 `aggregate`（单仓）和 `topology`（无跨项目集成）可使用。

<!-- APPEND_FLOW -->

## 十阶段执行流程

被触发时，先运行 `plan` 并让用户确认一次系统边界，再连续推进可自动阶段。将模块边界、Core Spec 候选和证据冲突合并成一次 owner 评审，避免逐条打断。每阶段执行“调用下层能力 → 校验产物 → 过关卡 → `mark`”。

### ① fetch — 拉取/定位项目 [自动]

- 用户给本地路径就直接用;给 git url 则 clone 到工作区目录(已存在跳过)。
- `plan` 会探测每个仓角色与栈。**关卡**:跟用户确认哪个是后端/前端、是否同属一个系统。
- 完成 → `mark --stage fetch`。

### ② profile — 项目画像 + Agent 入口 [AI起草+人确认]

- AI 读顶层/包结构/配置/构建文件,识别技术栈、分层、**编码(GBK?UTF-8?)**、启动方式。
- 按 `domain-knowledge-bootstrap` 的入口选择规则维护：Claude Code 用 `CLAUDE.md`，Codex/Cursor 用 `AGENTS.md`，多工具团队双写同步。
- 前后端分离 → **每个仓各写自包含的适用 Agent 入口且互相指向**;不要只在其中一个仓写一份。
- **关卡**:技术栈识别对不对、编码判定对不对(GBK 项目要警示乱码,UTF-8 不必)。
- 完成 → `mark --stage profile`。

### ③ coding — 编码 profile [AI起草+人确认]

- 调用 `project-coding-profiles`，生成 `profiles/<project>/{profile.json,coding-mode.md}`。
- 填写并验证项目独有 `rootMarkers`、encoding 与 codingMode。
- GBK 老项目重点启用编码守护；UTF-8 框架项目重点记录分层与脚手架约定。
- **关卡**：rootMarkers 能命中真实项目根，编码/框架定性正确。
- 完成 → `mark --stage coding`。

### ④ aggregate — 多仓聚合 [自动，调 yoooni-taskspace]

- 仅前后端分离或多仓系统执行 `pipeline.mjs aggregate`，创建 junction/symlink 工作区。
- 系统级 Agent 入口记录全景和仓库对接关系；聚合工作区通常不进 Git。
- 单仓项目 → `mark --stage aggregate --status skipped`。
- 多仓完成 → `mark --stage aggregate`。

### ⑤ graphify — 实现事实图谱 [自动扫描+AI健康检查]

- 调用 `graphify` Skill；单仓运行 `/graphify <repo> --directed`，多仓使用 Graphify 的多路径合并能力，不重写抽图逻辑。
- 产物至少包含 `graphify-out/graph.json`、`GRAPH_REPORT.md` 与健康检查结果。
- 已存在且与代码一致时复用；代码变化时按 Graphify 规范增量更新。
- **关卡**：图非空；健康告警已显式记录；`graph.json` 路径可供 Core Spec 引证。
- 完成 → `mark --stage graphify`。

### ⑥ knowledge — 领域知识、模块地图与 DDL [人判定，调 domain-knowledge-bootstrap]

- **调用 `domain-knowledge-bootstrap` skill**(在 project-domain-knowledge 仓库),不在这里重写。
- 先同步 `knowledge/<project>/impl/modules.json`，再逐模块扫描并起草 `draft` 业务真理。
- DB 项目必须从真实 schema 生成 `knowledge/<project>/impl/ddl-baseline.md`；禁止仅按 ORM 或类名猜表字段。
- **填 modules.json 后必跑 `check-paths` 校验**:codePath/webPaths 是否真实存在——
  前端 `webPaths` 全靠人工填、最易写错(写了不存在的目录 / 漏真实业务目录 / 把单文件当模块);
  一个后端模块前端常散在多个目录,`webPaths` 用数组列全。命令:
  `node scripts/bootstrap.mjs check-paths --project <P> --backend-root <后端根> --frontend-root <前端根>`。
- Graphify 是实现事实引用，不能替代业务 owner；纯推断必须保持 `draft`。
- **关卡**：模块边界、DDL 来源和业务真理候选已核对，`check`、`check-paths`、`catalog` 通过。
- 完成 → `mark --stage knowledge`。

### ⑦ core-spec — 全模块 Core Spec 静态候选 [自动起草+人评审]

- 在 `project-domain-knowledge` 执行：

```powershell
node scripts/bootstrap.mjs draft-all --project <P> --project-root <项目根> --graph <graph.json> --apply
```

- 为 `modules.json` 中所有模块生成对象、关键字段、读写点、状态迁移、不变量和闭环候选。
- 静态候选不得自动晋升 stable。生成后 → `mark --stage core-spec --status needs-review`。
- owner 结合证据完成评审后 → `mark --stage core-spec --status done`。

### ⑧ evidence — 运行证据与规格挖掘 [自动采集+人评审]

- 从接口/审计日志、数据库变更、消息事件或历史记录采集对象事件，执行 `spec-mine init/mine`。
- 生成 OCEL 2.0、对象关系、状态迁移、不变量、闭环和冲突候选；Graphify 只作为静态证据引用。
- 有证据 → 将候选与冲突交 owner 执行 `review/promote`，通过后标记 `done`。
- 暂无可访问运行数据 → 初始化采集配置并执行：

```powershell
node pipeline.mjs mark --name <系统> --stage evidence --status waiting-evidence
```

- 禁止把 `waiting-evidence` 报告成“业务闭环已验证”。

### ⑨ topology — 跨项目拓扑 [人判定，归 cross-project-topology]

- 若发现本系统调用其它系统(如 .env 里指向别的服务、Feign 调外部),
  这类**跨 ≥2 项目**的调用链归 `cross-project-topology`,**不进本系统两仓也不进 domain-knowledge**。
- **关卡**:有没有跨项目集成、要不要登记。没有就 `--status skipped`。
- 完成 → `mark --stage topology`。

### ⑩ verify — 验证、评审与发布 [机械检查+人确认]

- 检查 Graphify 新鲜度、知识库 `check/check-paths/catalog`、Core Spec 候选状态和证据来源。
- 确认未经 owner 接受的候选仍为 draft；调用 MCP `reload_knowledge` 使已确认内容生效。
- 输出仓库边界、各阶段状态、产物路径、覆盖模块和剩余缺口。
- 存在 `pending/needs-review/waiting-evidence` 时如实列出，不宣称全闭环；CLI 会拒绝提前把 `verify` 标记为 `done`。

## 收尾

- `pipeline.mjs status` 出总进度。
- 各产物分别提交到**各自的仓**(知识图谱→domain-knowledge / profile→coding-profiles /
  CLAUDE.md/AGENTS.md→各项目仓),走 team-standards 的 git-commit-standards;聚合工作区不提交。
- 汇总：系统边界、Graphify 产物、领域知识与 DDL、Core Spec 覆盖模块、证据状态、编码 profile、Agent 入口和拓扑登记。

## 工作台一键

工作台对一个项目只暴露一次“初始化”操作，传入系统名与仓库路径后触发本 Skill，从 `plan` 开始断点续跑。用户只需确认系统边界和最终候选评审；底层仍保留可审计的阶段状态，不伪装成无人值守业务决策。

## 与下层能力的关系（不重造）

| 阶段 | 调用 |
|---|---|
| ③ coding | project-coding-profiles |
| ④ aggregate | yoooni-taskspace |
| ⑤ graphify | graphify Skill |
| ⑥ knowledge | domain-knowledge-bootstrap + DDL baseline |
| ⑦ core-spec | bootstrap.mjs draft-all |
| ⑧ evidence | spec-mining.mjs init/mine/review/promote |
| ⑨ topology | cross-project-topology |

本 skill 只做编排与关卡,逻辑都在下层。
