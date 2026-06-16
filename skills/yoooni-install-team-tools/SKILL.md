---
name: yoooni-install-team-tools
description: 一键拉取并安装公司团队工具（全部走 Gitee 源）。当用户说"安装公司插件/MCP"、"拉一下团队工具"、"装 team-standards / project-coding-profiles / project-domain-knowledge / cross-project-topology"、"配置公司开发规范插件"、"一键安装团队规范"、"新机器装一下团队插件"时触发。覆盖：两个 Claude Code 插件（team-standards 编码规范、project-coding-profiles 编码画像）+ 两个 MCP 实例（同一引擎：domain-knowledge 业务认知 + cross-topology 跨项目拓扑）。公司当前用 Gitee 管理源码，安装地址一律用 Gitee。
---

# 一键安装公司团队工具 Skill

把公司当前维护的几个 Claude Code 工具一次性拉取并安装到本机。**源码统一走 Gitee**（GitHub 仅部分仓库镜像，安装一律用 Gitee 地址）。

## 四个仓库 & 安装方式

| 仓库 | 类型 | 安装方式 | Gitee 地址 |
|---|---|---|---|
| `team-standards` | Claude Code 插件 | `/plugin marketplace add` + `/plugin install` | `https://gitee.com/wyoooni/team-standards.git` |
| `project-coding-profiles` | Claude Code 插件 | `/plugin marketplace add` + `/plugin install` | `https://gitee.com/wyoooni/project-coding-profiles.git` |
| `project-domain-knowledge` | MCP 引擎 + 业务认知 | git clone + `npm install && npm run build` + `claude mcp add` | `https://gitee.com/wyoooni/project-domain-knowledge.git` |
| `cross-project-topology` | MCP（复用上面的引擎） | git clone + `claude mcp add`（同一 server.js，`DOMAIN_KB_DIR` 指向本仓库） | `https://gitee.com/wyoooni/cross-project-topology.git` |

- **插件**（team-standards / project-coding-profiles）：通过 `/plugin` slash 命令安装，**只能在 Claude Code 会话里手动执行**（脚本无法代敲）。
- **MCP（一个引擎，两个实例）**：`project-domain-knowledge` 的 `dist/server.js` 是通用 md+frontmatter 知识引擎，靠 `DOMAIN_KB_DIR` 环境变量指向不同知识根目录。脚本用**同一份 server.js 注册两个 MCP 实例**：
  - `domain-knowledge` → 业务公共认知（`project-domain-knowledge/knowledge`）
  - `cross-topology` → 跨项目拓扑（`cross-project-topology/knowledge`）
  
  两个实例内容/生命周期分开（业务真理 vs 当前调用链），但共用引擎二进制——`cross-project-topology` 自己**无需 build、无需 package.json**。
- **前提**：引擎只索引 frontmatter 含 `id` 的 .md。`cross-project-topology` 内容须放在 `knowledge/{生态}/{拓扑类型}/{id}.md`（沿用 domain-knowledge 的 project×module 布局）。若该仓库尚无 `knowledge/` 根目录，脚本会跳过 `cross-topology` 注册并提示——内容就绪后重跑即可。

## 触发条件

- "安装公司插件"、"装一下团队工具"、"一键安装团队规范"
- "装 team-standards / project-coding-profiles / project-domain-knowledge / cross-project-topology"
- "新机器配置公司开发规范"、"拉一下公司的 plugin 和 mcp"

## 前置检查

| 工具 | 用途 | 缺失影响 |
|---|---|---|
| `git` | 克隆/更新全部仓库 | **必需**，缺失则中止 |
| `node` / `npm`（>=18） | 构建 project-domain-knowledge MCP | 缺失则跳过 MCP 构建，其余照常 |
| `claude` CLI | 注册 MCP（`claude mcp add`） | 缺失则跳过注册，打印手动命令 |

```powershell
git --version
node --version
npm --version
claude --version
```

## 执行步骤

### Step 1：运行一键脚本（自动完成 git + MCP 部分）

脚本 [install-team-tools.ps1](install-team-tools.ps1) 会：拉取/更新四个仓库 → 构建并注册 domain-knowledge MCP → 打印两个插件的安装命令。

```powershell
# 默认克隆到 %USERPROFILE%\myWork，MCP 注册为 user 范围（全局可用）
powershell -ExecutionPolicy Bypass -File "<plugin>\skills\yoooni-install-team-tools\install-team-tools.ps1"

# 自定义工作区目录 / MCP 范围
powershell -ExecutionPolicy Bypass -File ".\install-team-tools.ps1" -WorkspaceDir D:\Users\zhang\myWork -McpScope user
```

> `<plugin>` 为本插件安装路径。若不确定，直接用本仓库内脚本的绝对路径运行。
> 已存在的仓库会 `git pull --ff-only` 更新，不会重复克隆——**重复运行安全**（幂等）。
> MCP 注册幂等：脚本先 `claude mcp remove` 再 `claude mcp add`。

脚本默认参数：
- `-WorkspaceDir`：仓库克隆根目录，默认 `%USERPROFILE%\myWork`。
- `-McpScope`：`user`（默认，全局可用）/ `local` / `project`。

### Step 2：在 Claude Code 里安装两个插件（slash 命令）

脚本结束会打印这几条；逐条在 **Claude Code 会话**里执行（脚本无法代敲 slash 命令）：

```
/plugin marketplace add https://gitee.com/wyoooni/team-standards.git
/plugin install team-standards@team-standards

/plugin marketplace add https://gitee.com/wyoooni/project-coding-profiles.git
/plugin install project-coding-profiles@project-coding-profiles

/reload-plugins
```

### Step 3：验证

```powershell
# 仓库都已拉到本地
Get-ChildItem "$env:USERPROFILE\myWork" | Where-Object Name -in 'team-standards','project-coding-profiles','project-domain-knowledge','cross-project-topology'

# MCP 已注册（两个实例）
claude mcp list
```

- 在 Claude Code 里 `/plugin`（或 `/help`）能看到 team-standards、project-coding-profiles。
- `claude mcp list` 能看到 `domain-knowledge` 和 `cross-topology`（若 topology 仓库已建 `knowledge/` 根目录）。

## 各工具装好后做什么

- **team-standards**：团队通用开发规范（Java/Dart 编码、设计文档强制约束、Git 提交规范），自动按 skill 触发。
- **project-coding-profiles**：项目级编码画像（GBK/UTF-8 编码守护、模块脚手架），在已登记的项目内触发。
- **domain-knowledge**（MCP）：业务公共认知库，AI 遇到流程/状态/计算公式时自助查询。改完知识点用 MCP 工具 `reload_knowledge` 免重启生效。
- **cross-topology**（MCP，复用同一引擎）：跨项目调用链/拓扑登记库，AI 追跨项目链路时自助查询（search → get_knowledge → get_related 看关联）。同样支持 `reload_knowledge`。

## 常见坑

### `'git' / 'node' / 'claude' 不是内部或外部命令`
对应工具未安装或未加入 PATH。git 必需；node/npm 用于 MCP 构建；claude CLI 用于 MCP 注册。装好重开终端再跑。

### `git clone` 卡住 / 连不上 Gitee
确认网络可达 Gitee：`Test-NetConnection -ComputerName gitee.com -Port 443`。
若需 Gitee 账号鉴权，配置好凭据（`git config --global credential.helper manager`）或在 Gitee 配置 SSH/Token 后重试。

### `npm run build` 失败
确认 node 版本 >=18（`node --version`）。删 `node_modules` 后重试：`Remove-Item -Recurse -Force node_modules; npm install; npm run build`。

### MCP 注册后 Claude Code 看不到 domain-knowledge
- 确认 `dist\server.js` 已生成（build 成功）。
- 确认注册范围：`user` 全局可用；`project`/`local` 只在对应项目可见。
- 重启 Claude Code 会话或 `/mcp` 刷新。

### `/plugin install` 报 `Invalid JSON ... Unrecognized token`
插件仓库的 manifest 是带 BOM 的 JSON 导致。这是**插件仓库侧**问题（见各仓库 CLAUDE.md 的无 BOM 写法），与本机无关，需仓库维护者修复。

### 已经装过想更新
重复运行脚本即可（`git pull` 更新 + 重新 build/注册 MCP）。插件更新：
```
/plugin marketplace update team-standards
/plugin install team-standards@team-standards
/plugin marketplace update project-coding-profiles
/plugin install project-coding-profiles@project-coding-profiles
```
