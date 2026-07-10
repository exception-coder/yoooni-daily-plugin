---
name: yoooni-devmodule-scaffold
description: 给某个项目在 kai-toolbox 工作台里生成一个「XX 需求开发」模块——参考已落地的「ERP 需求开发」范式，自动整理出：选工作目录 + 模块/需求(记住上次输入) + 服务启停 + 前台日志(SSE+放大) + 调试必备配置 + 一键投喂大脑 skill 的门控开发工作台。通用骨架复用公共 devkit(features/_devkit + 后端 dev-service 多实例底座)，差异部分(启停命令、端口、调试配置字段、大脑触发口径)按项目填。当用户说"给 XX 项目做一个需求开发模块"、"参考 ERP 需求开发脚手架一个开发模块"、"scaffold 一个开发工作台"、"给 kai-toolbox 自己也整一个开发模块"、"新项目接入开发工作台"时触发。机械步骤(建 feature/接线/复用 devkit)自动跑，需判断的节点(项目差异项、生成文件清单、DB/配置改动)设人工关卡，只改不提交。
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

### ④ 生成后端配置（仅当①有调试配置）[半自动 · 关卡③]

- 照 `ErpDbConfigService`/`ErpAppConfigService`：`<X>ConfigService`（KV 表 `claude_chat_setting`，name=模块 id，含密码留空保留、脱敏视图）+ `<X>Controller`（`/api/claude-chat/<id>/config` GET脱敏/PUT + test）。
- **关卡③**：任何新增表/字段/迁移单独确认（本骨架优先用现成 `claude_chat_setting` KV，通常无需新表）。

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
