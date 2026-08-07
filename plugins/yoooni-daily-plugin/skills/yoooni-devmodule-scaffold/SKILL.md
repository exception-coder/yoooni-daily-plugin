---
name: yoooni-devmodule-scaffold
description: 为项目在 kai-toolbox 中生成需求开发工作台模块。用户要求参考 ERP 范式、scaffold 开发模块或让新项目接入工作台时使用。
---

# 项目「需求开发」工作台模块脚手架

把「给一个项目做一个 kai-toolbox 开发工作台模块」编排成一条**门控流水线**，产出物参照已落地的 **ERP 需求开发**（`frontend/src/features/erp-dev`）——它是本 skill 的**唯一范本**。通用骨架复用公共 devkit，项目差异按项目填。

**定位**：编排器，不是黑盒。建 feature、接线、复用 devkit 这些机械步骤自动跑；项目差异项、要生成的文件清单、任何 DB/配置改动，停下让人拍板。

## 触发条件

- "给 XX 项目做一个需求开发模块" / "参考 ERP 需求开发脚手架一个开发模块"
- "scaffold 一个开发工作台" / "新项目接入开发工作台"
- "给 kai-toolbox 自己也整一个开发模块"

## 红线（务必遵守）

- ❌ **不重造公共能力**：服务启停+日志一律用 `@/features/_devkit/DevServiceSection`（后端 `DevServiceController` 多实例底座，按 `serviceId` 键控），**不再抄一份**。
- ❌ **路由组件必须 `React.lazy`**：kai-toolbox 靠代码分割，manifest 里页面必须 `lazy(() => import(...))`，不能静态 import（否则拖垮首屏，见 kai-toolbox `CLAUDE.md`）。
- ❌ **配置落 SQLite，不落散 JSON**：需持久化的调试配置存 `claude_chat_setting` KV 表（`ClaudeChatSettingRepository`），照 `ErpDbConfigService`/`ErpAppConfigService` 范式；**不要**新建 `~/.kai-toolbox/*.json`。
- ✅ **配置区按项目定制，对不上的 tool 就补新增对接**：调试配置区不是照抄 ERP 那两块，而是按目标项目技术栈填（库类型、实例鉴权方式各不同）。若复用的大脑现有 MCP 工具（`erp_db`=Oracle / `erp_app`=*.action）与目标项目对不上，**就补一套新对接**：后端 `<X>ConfigService`+`<X>Controller`+执行器（`/query` 或 `/call`）+ sidecar 新 MCP 工具（`sessionManager.ts` 里与 erp_* 并列注入）+ 触发语显式点名新工具名。新增 JDBC 驱动等依赖属关卡③。**不改团队大脑插件本体**（如 `yoooni-erp-auto-dev`），差异靠触发语点名新工具吸收。
- ❌ **只改不提交**：改完出 diff 给人看，不 git add/commit/push。
- ✅ **FeatureManifest 图标用组件引用**（Lucide 组件，非字符串）；`group` 归「AI 工具」，`layout` 默认 `tool`。
- ✅ **先读范本**：动手前先读 `frontend/src/features/erp-dev/**` 与 kai-toolbox `CLAUDE.md`（架构·tool 插入约定），照着来。

## 前置

- 在 **kai-toolbox 仓**可写的机器上；公共底座已在（`features/_devkit/DevServiceSection.tsx` + 后端 `DevServiceController`/`DevServiceManager`）。
- 目标项目已在某工作区根下（`toolbox.claude-chat.workspace.roots`），能在「工作区目录」下拉里选到。

## 通用骨架 vs 项目差异

| 层 | 通用（直接复用，不用改） | 项目差异（本 skill 要问清） |
|---|---|---|
| 表单 | 选工作目录 + 模块 + 需求，记住上次输入(localStorage) | 模块下拉来源、需求占位文案 |
| 服务启停+日志 | `<DevServiceSection serviceId=... />`（启停/重启/前台日志/放大） | `serviceId`、`defaultCommand`(启动命令)、可选 `stopCommand`、标题 |
| 调试必备配置 | 折叠配置区 + `claude_chat_setting` KV 持久化 + 脱敏视图 | **有哪些字段**（ERP=Oracle只读库+本地实例；别的项目按需） |
| 大脑 | 投喂触发语拉起门控流水线 skill | 触发语口径、复用 `yoooni-erp-auto-dev` 还是新建项目大脑 |

## 门控流程

被触发时，先复述「给哪个项目做、模块 id 叫什么」，再逐步推进。每步：做事 → 过关卡 → 下一步。

### ① 收集项目差异项 [关卡①]

问清并复述确认：
- **模块 id**（英文短横线，如 `kai-dev`）+ **中文名**（如「kai-toolbox 开发」）+ 侧边栏图标（Lucide 组件名）。
- **启停**：`serviceId`（通常=模块 id）；`defaultCommand`（前台启动命令）**不强制用户给**——用户没填就**到项目根目录探索启停脚本**（常见 `start-*.ps1` / `stop-*.ps1`、`package.json` 的 scripts、`pom.xml`/`mvn`），识别出的启动/停服命令作为 `defaultCommand`/`stopCommand`，在关卡①念给用户确认；探索不到停服命令就默认结束进程树。
- **调试必备配置**：这个项目跑起来/调试**必须**的配置项有哪些（DB？实例地址？账号密钥？没有就跳过配置区）。
- **大脑**：复用 `yoooni-erp-auto-dev`（若也是 ERP 类），还是新建一个项目专属大脑 skill（另走 skill 编写）；先定触发语。
- **关卡①**：以上念给用户确认，尤其"差异项到底差哪些"。

### ② 读范本 + 规划文件清单 [关卡②]

- 读 `frontend/src/features/erp-dev/{index.tsx,api.ts,pages/ErpDevPage.tsx}`、`features/_devkit/*`、kai-toolbox `CLAUDE.md`。
- 列出要**新增/修改**的文件清单（见下「产出物」），**关卡②**念给用户确认后再写。

### ③ 生成前端 feature [自动 · 机械]

- `frontend/src/features/<id>/index.tsx`：默认导出 `FeatureManifest`（`id`/`name`/`icon` 组件引用/`group:'AI 工具'`/`order`/`routes`，页面用 `React.lazy`）。
- `pages/<Id>Page.tsx`：
  - 表单：工作区目录下拉（拍平 `listWorkspaces`）+ 模块 + 需求，**三者记 localStorage**（键带模块 id）；
  - `<DevServiceSection serviceId="<id>" dirs={dirs} defaultCwd={cwd} defaultCommand="<启动命令>" title="<中文名> 服务启停 + 启动日志" />`；
  - 调试配置区（若①有）：折叠 `<details>`，字段照 `ErpDbConfigSection` 写法，走后端 KV；
  - 「开始开发」：拼触发语写 `sessionStorage` handoff → 跳 Vibe Coding（照 `erp-dev` 的 `LAUNCH_KEY` 范式）。

### ④ 生成后端配置 + 按需补对接（仅当①有调试配置）[半自动 · 关卡③]

- 照 `ErpDbConfigService`/`ErpAppConfigService`：`<X>ConfigService`（KV 表 `claude_chat_setting`，name=模块前缀如 `srm-db`/`srm-app`，含密码留空保留、脱敏视图）+ `<X>Controller`（`/api/claude-chat/<name>/config` GET脱敏/PUT + test）。
- **对不上就补新对接**：目标项目库/实例与 erp_db(Oracle)/erp_app(*.action) 不同则新写执行器 + sidecar MCP 工具（见红线「配置区按项目定制」）。查询/调用结果 DTO 可复用通用的 `ErpDbQueryResult`/`ErpAppCallResult`（非 ERP 专属，纯数据壳）。
- **关卡③**：任何新增表/字段/迁移或新增 Maven/npm 依赖单独确认（本骨架优先用现成 `claude_chat_setting` KV，通常无需新表；新增 JDBC 驱动等依赖要念给用户）。

### ⑤ 自检 + 出 diff [自动 · 只改不提交]

- 前端 `npm run typecheck`；动了后端则 `mvn -pl tools/tool-claude-chat -am compile -DskipTests`。
- 出 diff 摘要（新增哪些文件、每处为什么），**停在这里不提交**，提示 review。

## 产出物（典型）

```
frontend/src/features/<id>/index.tsx           # FeatureManifest（侧边栏+路由，lazy 页面）
frontend/src/features/<id>/pages/<Id>Page.tsx  # 表单 + DevServiceSection + 调试配置 + handoff
frontend/src/features/<id>/api.ts              # （仅当有调试配置）配置读写客户端
tools/.../<X>ConfigService.java + <X>Controller.java   # （仅当有调试配置）KV 持久化
```
服务启停/日志**零新增代码**——直接用 devkit。

## 与下层能力的关系（不重造）

| 步骤 | 复用 |
|---|---|
| 服务启停+日志 | `features/_devkit/DevServiceSection` + 后端 `DevServiceController`（多实例，按 serviceId） |
| 配置持久化 | `claude_chat_setting` KV + `ClaudeChatSettingRepository`（照 ErpDb/ErpApp） |
| 侧边栏/路由 | kai-toolbox `featureRegistry`（放 `features/<id>/index.tsx` 即自动收录，无需改路由） |
| 大脑 | `yoooni-erp-auto-dev`（ERP 类可复用）或项目专属大脑 skill |

本 skill 只做**编排与门控 + 按范本生成接线**，运行时能力都在 devkit/后端底座里。

## 首个落地：kai-toolbox 自身（dogfood）

- 模块 id `kai-dev`、中文名「kai-toolbox 开发」；`defaultCommand` 前端 `npm run dev`（或后端 `mvn -pl toolbox-starter -am spring-boot:run`，二者可各配一个 serviceId）；调试配置项按需（多数无）；大脑可先复用通用门控口径。

## 第二个落地：SRM 需求开发（补新对接 + 多服务启停的范例）

- 模块 id `srm-dev`、中文名「SRM需求开发」、图标 `Handshake`；目标项目=芋道 Spring Cloud 微服务 + Vue2 前端 + MySQL（聚合工作区 `srm-system`，启停脚本在其根）。
- **启停**：单块 `DevServiceSection serviceId="srm"`，`defaultCommand`/`stopCommand` 接聚合脚本 `start-srm.ps1 -Foreground`/`stop-srm.ps1`。
  - ⚠️ **扇出型 launcher 陷阱**：若启动脚本用 `Start-Process` 把各服务甩到独立窗口后自身立刻返回（`exit=0`），devkit 的「一进程+抓 stdout+按存活判状态」模型会失配——工作台判「已退出」且抓不到任何日志。**解法（脚本适配，优先）**：给脚本加 `-Foreground` 合并前台模式——各服务作为**本进程真子进程**跑（`Start-Process -NoNewWindow` + 重定向临时文件），输出按 `[服务名]` 前缀**合并**打到本进程 stdout 并**阻塞**等待；停服对进程树整体 kill 即全带走。人肉多窗口默认不变。次选（工作台适配）：拆成多个单服务 `DevServiceSection`，但会把 JVM 参数/端口从脚本抄进前端、易漂移。
  - 🟢 **多服务就绪可视化**：单窗口合并后「哪些子服务起好了」看不出来——给 `DevServiceSection` 传可选 `readinessPorts=[{label,port}...]`，它按 label 显示就绪徽标条，由 devkit 后端 `GET /api/claude-chat/dev-service/ports?ports=…`（本机 TCP 探端口，绕开浏览器直连后端端口的 CORS 限制）每 4s 判绿/灰。SRM 传了 gateway:8887/infra:8888/system:8889/frontend:81。此为 devkit 通用能力，任意模块可复用。
- **配置区（对不上 → 补对接）**：erp_db 是 Oracle、erp_app 是 *.action，均与 SRM 不符，故新增：
  - 后端 `SrmDbConfigService`+`SrmDbController`+`SrmDbService`（MySQL 只读，`jdbc:mysql`，复用 SELECT-only 闸 + `ErpDbQueryResult` DTO）；pom 加 `mysql-connector-j`（关卡③）。
  - 后端 `SrmAppConfigService`+`SrmAppController`+`SrmAppService`（yudao OAuth2 密码登录取 `data.accessToken`，后续带 `Authorization: Bearer` + `tenant-id` 头；复用同源白名单 + 拒生产域 + `ErpAppCallResult` DTO）。
  - sidecar `srmDb.ts`/`srmApp.ts` 暴露 `mcp__srm_db__query` / `mcp__srm_app__http_call`，`sessionManager.ts` 与 erp_* 并列注入。
- **大脑**：复用 `yoooni-erp-auto-dev`（不改其本体），触发语按 SRM 改口径（domain-knowledge project=srm、前端 `src/api/<域>` ↔ 后端 `controller/admin/srm/<E>Controller`、MySQL DDL 为准、芋道分层），并显式点名 `mcp__srm_db__query`/`mcp__srm_app__http_call` 做自闭环验证。
