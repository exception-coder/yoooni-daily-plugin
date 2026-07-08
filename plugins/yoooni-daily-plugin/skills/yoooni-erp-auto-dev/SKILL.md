---
name: yoooni-erp-auto-dev
description: ERP 小需求自动开发编排——只给「模块名(中文名或粘 URL) + 需求描述」，就自动【定位页面代码 → 查业务知识图谱 → 查库结构/状态字典 → 出轻量方案 → 按编码规范改码 → 自检出 diff】，把公司已沉淀的知识图谱/编码画像/URL 路由表串成一条可门控、可断点的开发流水线。当用户说"开发一个 ERP 需求"、"ERP 小需求"、"给你模块名和需求你来改"、"帮我改这个页面(粘了 *.action / URL)"、"按需求改 XX 模块"、"自动开发 erp"时触发。编排已有能力(url-locate / domain-knowledge MCP / cross-topology / project-coding-profiles / team-standards 的 design-doc·pre-implementation)，机械步骤自动跑，需判断的节点(命中页面、方案、DB/迁移改动)设人工关卡，只改不提交、不做无人值守黑盒。
---

# ERP 小需求自动开发 Skill

把「接一个 ERP 小需求」的全套动作编排成一条**门控流水线**：**定位页面代码 → 查业务知识图谱 → 查库 → 出方案 → 按规范改码 → 自检出 diff**。输入只要两样：**模块（中文名 或 粘一个页面 URL/\*.action）+ 需求描述**。

**定位**：编排器，不是黑盒。机械步骤（定位、查图谱、查库、编译自检）自动跑；需判断的节点（命中的是不是目标页面、方案对不对、要不要动 DB）停下来让人拍板。复用公司已沉淀的能力，不重造。

## 触发条件

- "开发一个 ERP 需求" / "ERP 小需求" / "自动开发 erp"
- "给你模块名和需求，你来改" / "按需求改 XX 模块"
- "帮我改这个页面" + 粘了 `xxx.action` / `localhost/...` / 菜单 URL

## 红线（务必遵守）

- ❌ **不无人值守**：命中页面、实现方案、任何 DB/迁移/状态字典改动，都要过人工关卡，人点头才继续。
- ❌ **不重写下层逻辑**：定位走 `url-locate`、业务口径走 `domain-knowledge` MCP、编码规范走 `project-coding-profiles`/`team-standards`，一律调用、不在本 skill 复刻。
- ❌ **只改不提交**：改完留在工作区、出 diff 给人看，**不 git add/commit/push**（提交由人确认后自行进行）。
- ✅ **业务真相以知识图谱/DB 为准**：口径先查 `domain-knowledge`；状态字典/表结构以 **DDL/SQL 脚本**与库为可信来源，优先于类名推断。
- ✅ **编码安全**：ERP 老工程可能是 GBK，改文件前遵守 `encoding-guard`（探测编码→安全回环写入），防中文乱码。

## 前置

- 在能访问 ERP 项目代码的机器上，且团队套件已装（`yoooni-install-team-tools`）：`domain-knowledge` / `cross-topology` MCP、`project-coding-profiles`、`team-standards` 均可用。
- 已授权的库查询通道（查表结构/状态字典）。

## 五步门控流程

被触发时，先把「模块 + 需求」复述确认范围，再逐步推进。每步：做事 → 过关卡（让用户拍板）→ 下一步。

### ① 定位页面代码 [半自动 · 关卡]

- **给了 URL / `*.action`**：调 `url-locate`（查该项目 profile 的 `url-route-map.md`）直达后端 Action 类 + 前端 jsp/页面，只读命中的相关文件，不全项目扫。
- **只给了中文模块名**：用 `domain-knowledge` 的 `list_modules` / 模块→代码映射 定位模块目录与关键类；必要时结合项目 `url-route-map`。
- **关卡①**：把命中的页面 / 后端类 / 前端文件念给用户——"要改的是不是这个？"。确认后继续。

### ② 查业务知识图谱 + 库 [自动]

- `domain-knowledge` MCP：`get_knowledge` / `search_knowledge` 拉该模块的业务口径、术语、状态机、字段含义。
- 跨系统集成关系（若涉及）查 `cross-topology`。
- **查库**：优先用只读工具 **`mcp__erp_db__query`**（工作台配置的测试库，**只读** SELECT）取相关表结构、外键、
  **状态字典**、样本数据核对；也可参考仓内 DDL/SQL 脚本。以库/DDL 为准，纯类名推断的点标注清楚。
  该工具若回「未配置」，提示用户到「ERP 需求开发」填测试库只读连接。
- 汇总"这个需求涉及的业务真相与数据面"，供出方案用。

### ③ 出轻量方案 [半自动 · 关卡]

- 走 `team-standards` 的 `design-doc`（按改动体量选**极简/轻量**档，不写大文档）：改哪些文件、加/改哪些字段或接口、对既有逻辑与状态的影响、回归风险点。
- **关卡②**：方案念给用户确认。用户可让其调整方向后再改。

### ④ 按规范改码 [半自动 · 关卡]

- 先走 `pre-implementation`：从方案定位代码坐标，再动手。
- 严格遵守 `project-coding-profiles`（`encoding-guard` 编码安全、`module-scaffold` 若是新增模块则按范式）与 `team-standards`（分层/命名/注释红线）。
- **关卡③（重要）**：任何 **DB 结构变更 / 迁移脚本 / 状态字典新增** 单独停下确认——这类影响面大、需评审，人点头才写。
- 改动范围严格限定在方案确认的文件；发现方案外的必要改动，回到关卡②补确认。

### ⑤ 自检 + 出 diff [自动 · 只改不提交]

- 能编译/构建的就跑一次编译或该模块的最小验证；把关键结果贴出。
- 出本次改动的 **diff 摘要**（改了哪些文件、每处为什么）。
- **停在这里**：不提交。提示用户 review，确认后由用户（或另行）提交——遵守 `team-standards` 的 `git-commit-standards`。

## 收尾

- 汇总：本次改了哪个模块、依据了哪些知识图谱口径/库信息、动了哪些文件、有无 DB 改动（若有，单列）、回归风险点。
- 若过程中发现知识图谱缺口（业务口径没记/记错），提示用户走 `domain-knowledge` 补登，让下次更准。

## 与下层能力的关系（不重造）

| 步骤 | 调用 |
|---|---|
| ① 定位 | project-coding-profiles 的 `url-locate`（URL→代码）；`domain-knowledge` 模块映射（中文名→代码） |
| ② 查真相 | `domain-knowledge` / `cross-topology` MCP + `mcp__erp_db__query`（只读查测试库） |
| ③ 方案 | team-standards 的 `design-doc-required` |
| ④ 改码 | team-standards 的 `pre-implementation-code-orientation` + project-coding-profiles（encoding-guard / module-scaffold） |
| ⑤ 提交 | 只改不提交；提交时走 team-standards 的 `git-commit-standards`（由人确认） |

本 skill 只做**编排与门控**，逻辑都在下层。

## 工作台一键

kai-toolbox 工作台的「ERP 需求开发」模块对本 skill 暴露一个前门：填**模块名/URL + 需求**即在 ERP 工作区拉起一个 Claude 会话、投喂触发语从①走起，实时展示过程、关卡处停下等人拍板。底层仍是「编排 + 关卡」，不是无人值守。
