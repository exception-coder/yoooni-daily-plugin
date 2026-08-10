---
name: yoooni-erp-auto-dev
description: 编排 Yoooni ERP 小需求开发。用户提供模块名或页面 URL 加需求描述，要求定位页面、查询业务知识并完成受控改码时使用。
---

# ERP 小需求自动开发 Skill

把「接一个 ERP 小需求」的全套动作编排成一条**门控流水线**：**定位页面代码 → 查业务知识图谱与库 → 必要时挖掘对象规格 → 出方案 → 按规范改码 → 验证业务闭环 → 自检出 diff**。输入只要两样：**模块（中文名 或 粘一个页面 URL/\*.action）+ 需求描述**。

**定位**：编排器，不是黑盒。机械步骤（定位、查图谱、查库、编译自检）自动跑；需判断的节点（命中的是不是目标页面、方案对不对、要不要动 DB）停下来让人拍板。复用公司已沉淀的能力，不重造。

## 触发条件

- "开发一个 ERP 需求" / "ERP 小需求" / "自动开发 erp"
- "给你模块名和需求，你来改" / "按需求改 XX 模块"
- "帮我改这个页面" + 粘了 `xxx.action` / `localhost/...` / 菜单 URL

## 红线（务必遵守）

- ❌ **不无人值守**：命中页面、实现方案、任何 DB/迁移/状态字典改动，都要过人工关卡，人点头才继续。
- ❌ **不重写下层逻辑**：定位走 `url-locate`、业务口径走 `domain-knowledge` MCP、编码规范走 `project-coding-profiles`/`team-standards`，一律调用、不在本 skill 复刻。
- ❌ **不让 LLM 猜状态机**：对象、状态、字段语义、不变量和闭环候选必须来自已有业务真理或 `domain-spec-mining-required` 的证据链；候选不得自动升为稳定业务真理。
- ❌ **只改不提交**：改完留在工作区、出 diff 给人看，**不 git add/commit/push**（提交由人确认后自行进行）。
- ✅ **业务真相以知识图谱/DB 为准**：口径先查 `domain-knowledge`；状态字典/表结构以 **DDL/SQL 脚本**与库为可信来源，优先于类名推断。
- ✅ **编码安全**：ERP 老工程可能是 GBK，改文件前遵守 `encoding-guard`（探测编码→安全回环写入），防中文乱码。

## 前置

- 在能访问 ERP 项目代码的机器上，且团队套件已装（`yoooni-install-team-tools`）：`domain-knowledge` / `cross-topology` MCP、`project-coding-profiles`、`team-standards` 均可用。
- 已授权的库查询通道（查表结构/状态字典）。

## 七步门控流程

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

### ②A 对象中心规格挖掘 [条件自动 · 关卡]

当需求涉及订单、库存、标签、审核、取消、退货、调拨、占用等**业务对象状态或关联变化**，且现有知识点没有完整覆盖对象终态、关联解除、不变量或下一动作时，调用 team-standards 的 `domain-spec-mining-required`：

1. 先用 `list_spec_candidates` / `get_spec_candidate` 查询已有候选、反例和评审状态。
2. 候选缺失时，复用 Graphify `graph.json`、DDL/反向索引和已授权的日志、历史表或测试前后快照，运行 `project-domain-knowledge` 的 `spec-mining` CLI；不在本 Skill 内复制挖掘逻辑。
3. 输出本次对象闭环合同：
   - 操作前后对象状态；
   - 必须建立和解除的关联；
   - 数据库终态断言；
   - 事务失败与重复操作行为；
   - 至少一个下一业务动作。
4. 未解决的字段语义冲突、状态多目标或反例属于**关卡**，先请用户/业务 owner 确认，不能带冲突进入编码。

纯展示、文案、样式或不改变业务对象状态的极简修改跳过本步。已有 confirmed 规格完整覆盖且无新冲突时，只读取复用，不重复挖掘。

### ③ 出轻量方案 + 验收清单 [半自动 · 关卡]

- 走 `team-standards` 的 `design-doc`（按改动体量选**极简/轻量**档，不写大文档）：改哪些文件、加/改哪些字段或接口、对既有逻辑与状态的影响、回归风险点。
- **产出「验收清单」（自闭环验证的判据源头，务必给）**：把需求翻成若干条**可机检**的验收项，每条 =
  **触发动作**（调哪个 `*.action` + 请求参数）+ **期望结果**（HTTP 状态/响应体断言，和/或**回读 SQL** + 期望值），
  纯前端/展示项标注「人眼确认」。例：
  - 调 `saveAllcost.action`（`amount=100,type=1`）→ 期望 HTTP 200 且响应 `success=true`；
  - 回读 `SELECT status,amount FROM t_allcost WHERE id=?` → 期望 `status=1, amount=100`；
  - 打开 `allcost_list.action` → 期望列表首行金额显示 `100.00`（人眼确认）。
- 涉及对象状态时，验收清单必须覆盖**上游动作 → 当前动作 → 下游下一动作**，并直接断言关键数据库终态；只写“接口成功/审核成功/按钮成功”不算闭环。
- **关卡②**：方案 + 验收清单念给用户确认。用户可让其调整方向或补验收项后再改。

### ④ 按规范改码 [半自动 · 关卡]

- 先走 `pre-implementation`：从方案定位代码坐标，再动手。
- 严格遵守 `project-coding-profiles`（`encoding-guard` 编码安全、`module-scaffold` 若是新增模块则按范式）与 `team-standards`（分层/命名/注释红线）。
- **关卡③（重要）**：任何 **DB 结构变更 / 迁移脚本 / 状态字典新增** 单独停下确认——这类影响面大、需评审，人点头才写。
- 改动范围严格限定在方案确认的文件；发现方案外的必要改动，回到关卡②补确认。

### ⑤ 静态自检 [自动]

- 能编译/构建的就跑一次编译或该模块的最小验证；把关键结果贴出。编译不过先修好再进 ⑥。

### ⑥ 自闭环验证 [半自动 · 关卡 · 运行时]

按 ③ 的**验收清单**把改动真跑起来验，判据客观、留痕可回归。

- **a. 生效** [关卡④]：Java 类改动需重编译 + 重启本地实例才生效（纯 JSP 改动 Resin 热编译可跳过）。
  **重启会打断用户的调试会话，属人可感知动作**——停下提示用户「我已重编译/重启，继续验证」，**人点头才往下**，不擅自重启。
  工作台「ERP 服务启停」区可一键重启并实时看前台启动日志，等看到 `Resin started ... http listening` 再进探测。
- **b. 探测**：逐条跑验收项——
  - 调接口：`mcp__erp_app__http_call`（登录态实发 `*.action`，**只打本地/测试实例**）拿请求→响应；
  - 回读数据：`mcp__erp_db__query`（**只读** SELECT）核对数据落库效果；
  - 页面项：把目标 URL 念给用户/让其打开**人眼确认**（本期不做机器截图）。
  - 下一动作：对状态/关联变更实际执行至少一个后续动作，例如标签入仓后再次配货或调拨；不能只查当前接口响应。
- **c. 判定 + 出「接口验证区块」**：每条验收项按 `期望 vs 实际` 判 **PASS / FAIL**，并贴一张**接口验证区块**（这是执行留痕，不是文档描述）：

  ```text
  接口验证 · saveAllcost.action                         [PASS]
  1) 接口     POST /erp/allcost/saveAllcost.action（本次改动：金额校验分支）
  2) 请求参数  { amount: 100, type: 1 }
  3) 执行     → HTTP 200 · 218ms   ← { "success": true, "id": 90231 }
  4) 对应 SQL  SELECT status,amount FROM t_allcost WHERE id=90231 → status=1 amount=100.00
  判定        期望 success=true 且 status=1,amount=100 → 实际一致
  ```

- **d. 不符则修正回环**：有 FAIL → 带「实际现象」回 ④ 修正，再走 ⑤⑥；**迭代上限 3 次**，超限停下把「改了 N 次仍不符 + 现象」念给人（守红线，绝不静默死循环）。
- `mcp__erp_app__http_call` 回「未配置」时：告诉用户到「ERP 需求开发」配本地实例；本轮 ⑥ 退化为「只用只读回读判数据面 + 页面人眼确认」，并标注「接口未实发」。

### ⑦ 出 diff 收尾 [自动 · 只改不提交]

- 出本次改动的 **diff 摘要**（改了哪些文件、每处为什么）。
- **停在这里**：不提交。提示用户 review，确认后由用户（或另行）提交——遵守 `team-standards` 的 `git-commit-standards`。

## 收尾

- 汇总：本次改了哪个模块、依据了哪些稳定知识点与规格候选、候选证据/反例是否已解决、动了哪些文件、有无 DB 改动（若有，单列）、**数据库终态与下一动作验证结果（各接口验证区块 PASS/FAIL）**、回归风险点。
- 若过程中发现知识图谱缺口（业务口径没记/记错），提示用户走 `domain-knowledge` 补登，让下次更准。

## 与下层能力的关系（不重造）

| 步骤 | 调用 |
|---|---|
| ① 定位 | project-coding-profiles 的 `url-locate`（URL→代码）；`domain-knowledge` 模块映射（中文名→代码） |
| ② 查真相 | `domain-knowledge` / `cross-topology` MCP + `mcp__erp_db__query`（只读查测试库） |
| ②A 对象规格 | team-standards 的 `domain-spec-mining-required` + project-domain-knowledge 的 `spec-mining` CLI / 候选 MCP 工具 |
| ③ 方案 + 验收清单 | team-standards 的 `design-doc-required` |
| ④ 改码 | team-standards 的 `pre-implementation-code-orientation` + project-coding-profiles（encoding-guard / module-scaffold） |
| ⑤ 静态自检 | 编译/构建 |
| ⑥ 自闭环验证 | `mcp__erp_app__http_call`（登录态实发接口，只打本地/测试实例）+ `mcp__erp_db__query`（只读回读） |
| ⑦ 提交 | 只改不提交；提交时走 team-standards 的 `git-commit-standards`（由人确认） |

本 skill 只做**编排与门控**，逻辑都在下层。

## 简化后工作台入口

kai-toolbox 的「ERP 需求开发」页面已简化为**服务启停、启动日志、测试库和本地实例配置**，不再承载“模块/URL + 需求”表单，也不再从该页面自动创建会话。开发需求统一在 Vibe Coding 会话中直接输入**模块名/URL + 需求描述**来触发本 skill；本 skill 仍从①开始执行门控流水线，页面只提供运行与验证所需的环境能力。

禁止要求用户回到「ERP 需求开发」页面寻找“开始开发”按钮；需要启动本地服务或补齐测试库/实例配置时，才引导用户进入该页面。

该模块另有两处折叠配置，为 ②/⑥ 提供只读/探测通道（均存服务端、密码脱敏）：
- **测试库连接（只读）** → 后端只读执行器，喂 `mcp__erp_db__query`（②查真相、⑥回读）。
- **本地 ERP 实例（验证用）** → 后端登录态执行器，喂 `mcp__erp_app__http_call`（⑥实发接口）；后端强制同源白名单 + 拒生产域，只打本地/测试实例。
- **ERP 服务启停 + 启动日志** → 工作台托管拉起 Yoooni(Resin) 并实时看前台控制台日志，供 ⑥ 的「生效」步一键重启 + 确认启动成功（`Resin started`）。
