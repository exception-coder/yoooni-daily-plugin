---
name: yoooni-install-team-tools
description: 一键拉取并安装公司团队工具（全部走 Gitee 源）。当用户说"安装公司插件/MCP"、"拉一下团队工具"、"装 team-standards / project-coding-profiles / project-domain-knowledge / cross-project-topology"、"配置公司开发规范插件"、"一键安装团队规范"、"新机器装一下团队插件"时触发。覆盖：两个 Claude Code 插件（team-standards 编码规范、project-coding-profiles 编码画像）+ 两个 MCP 实例（同一引擎：domain-knowledge 业务认知 + cross-topology 跨项目拓扑）。脚本全自动（仓库 git clone + MCP 注册 + 插件 claude plugin CLI 安装），已安装的一律跳过、不重装、不更新——若检测到已安装，改用『更新公司套件』skill(yoooni-update-team-tools)。公司当前用 Gitee 管理源码，安装地址一律用 Gitee。全新机器用 scripts/bootstrap-install.ps1 一键引导（含本体 yoooni-daily-plugin 自身 + 定时自动更新注册），已装本体的机器才用 install-team-tools.ps1。
---

# 一键安装公司团队工具 Skill（首次安装专用）

把公司当前维护的几个 Claude Code 工具一次性拉取并安装到本机。**源码统一走 Gitee**（GitHub 仅部分仓库镜像，安装一律用 Gitee 地址）。

> **职责边界（重要）**：本 skill 只负责【首次安装缺失的部分】。
> **已安装的一律跳过，不重装、不更新。** 需要更新请改用 `yoooni-update-team-tools`（『更新公司套件』），
> 它会 `git pull` + 重建 MCP + `claude plugin update`。**别用安装脚本来"更新"。**

## 全新机器：一键引导脚本（含本体 + 定时自动更新）

`install-team-tools.ps1` 跑在**本体插件内部**，所以装不了本体自己、也不注册定时更新。**全新机器**请用引导脚本 `scripts/bootstrap-install.ps1`——它在 install-team-tools.ps1 之上多做两件事：(1) 克隆 + 安装**本体 `yoooni-daily-plugin`**；(2) 注册**定时自动更新**任务（默认每 1 小时）；中间的「关联插件 + MCP」直接委托 install-team-tools.ps1（幂等、已装跳过），不重复实现。

```powershell
# 全新机器：下载引导脚本再运行（之后全自动）
$u='https://gitee.com/wyoooni/yoooni-daily-plugin/raw/master/scripts/bootstrap-install.ps1'
irm $u -OutFile "$env:TEMP\boot.ps1"; powershell -ExecutionPolicy Bypass -File "$env:TEMP\boot.ps1"
```

- 已装好本体的机器，只想补装关联工具 / 重复跑安装 → 仍用下面的 `install-team-tools.ps1`（幂等）。
- 只改更新周期（不重装）→ `scripts\register-autoupdate-task.ps1 -EveryHours <小时>`（内容稳定后建议从 1 改回 2~4）。
- 定时任务是「会话外也保持最新」的兜底；「开 Claude Code 即刷新」由 SessionStart hook 负责，二者互补。

## AI 触发本 skill 时的判断逻辑

1. 用户说"安装/装一下" → 跑安装脚本（脚本内部对每一项已做"已存在则跳过"判断，重复运行安全）。
2. 若用户其实是想"更新/同步最新"（或脚本/检查显示各项均已安装）→ **不要重装**，转去 `yoooni-update-team-tools`。
3. 脚本结束的汇总会明确列出"本次新装"与"已安装未改动"，并提示更新走哪条路。

## 四个仓库 & 安装方式（均可脚本全自动）

| 仓库 | 类型 | 安装方式 | Gitee 地址 |
|---|---|---|---|
| `team-standards` | Claude Code 插件 | `claude plugin marketplace add` + `claude plugin install`（CLI，脚本自动） | `https://gitee.com/wyoooni/team-standards.git` |
| `project-coding-profiles` | Claude Code 插件 | 同上 | `https://gitee.com/wyoooni/project-coding-profiles.git` |
| `project-domain-knowledge` | MCP 引擎 + 业务认知 | git clone + `npm install && npm run build` + `claude mcp add` | `https://gitee.com/wyoooni/project-domain-knowledge.git` |
| `cross-project-topology` | MCP（复用上面的引擎） | git clone + `claude mcp add`（同一 server.js，`DOMAIN_KB_DIR` 指向本仓库） | `https://gitee.com/wyoooni/cross-project-topology.git` |

- **插件**（team-standards / project-coding-profiles）：`claude plugin` 现已是完整 CLI，脚本可**全自动安装**，无需手敲 `/plugin` slash。安装后**重启会话生效**（或 `/reload-plugins`）。插件名在 CLI 中须带 `@marketplace` 全限定（`team-standards@team-standards`），裸名会报 `not found`。
- **MCP（一个引擎，两个实例）**：`project-domain-knowledge` 的 `dist/server.js` 是通用 md+frontmatter 知识引擎，靠 `DOMAIN_KB_DIR` 指向不同知识根目录。脚本用**同一份 server.js 注册两个 MCP 实例**：
  - `domain-knowledge` → 业务公共认知（`project-domain-knowledge/knowledge`）
  - `cross-topology` → 跨项目拓扑（`cross-project-topology/knowledge`）
  
  两实例内容/生命周期分开，共用引擎二进制——`cross-project-topology` 自己**无需 build、无需 package.json**。
- **前提**：引擎只索引 frontmatter 含 `id` 的 .md。`cross-project-topology` 内容须放在 `knowledge/{生态}/{拓扑类型}/{id}.md`。若该仓库尚无 `knowledge/` 根目录，脚本会跳过 `cross-topology` 注册并提示——内容就绪后用 update skill 刷新即可。

## 前置检查

| 工具 | 用途 | 缺失影响 |
|---|---|---|
| `git` | 克隆全部仓库 | **必需**，缺失则中止 |
| `node` / `npm`（>=18） | 构建 project-domain-knowledge MCP | 缺失则跳过 MCP 构建，其余照常 |
| `claude` CLI | 注册 MCP + 安装插件 | 缺失则跳过，打印手动命令 |

```powershell
git --version; node --version; npm --version; claude --version
```

## 执行：一条命令全自动

脚本 [install-team-tools.ps1](install-team-tools.ps1)：克隆缺失仓库 → 构建并注册 MCP（domain-knowledge + cross-topology）→ 用 `claude plugin` CLI 安装两个插件。**每一项已安装则跳过。**

```powershell
# 不传参：自动定位工作区（复用已克隆目录，任意盘），MCP/插件装为 user 范围（全局）
powershell -ExecutionPolicy Bypass -File "<plugin>\skills\yoooni-install-team-tools\install-team-tools.ps1"

# 自定义工作区 / 安装范围
powershell -ExecutionPolicy Bypass -File ".\install-team-tools.ps1" -WorkspaceDir D:\Users\zhang\myWork -Scope user
```

- **工作区自动定位**（不传 `-WorkspaceDir` 时）：优先复用"已克隆过的目录"（参数 → `YOOONI_WORKSPACE_DIR` → 配置 `%USERPROFILE%\.kai-toolbox\workspace.path` → 从 `claude mcp get` 解析 → 跨盘 C/D/E/F 探测）；都没有才落到默认 `%USERPROFILE%\myWork`（全新机器首装）。**这避免了"明明 D 盘已克隆，却在默认 C 盘又克隆一份"。**
- `-Scope`：`user`（默认，全局）/ `local` / `project`，同时作用于 MCP 与插件。
- **重复运行安全**：仓库已存在不 pull、MCP 已注册不重注册、插件已装不重装——全部跳过并提示去用 update skill。

### 验证

```powershell
claude mcp list        # 应能看到 domain-knowledge 和 cross-topology
claude plugin list     # 应能看到 team-standards@team-standards、project-coding-profiles@project-coding-profiles
```

插件安装后需**重启 Claude Code 会话**才加载（或 `/reload-plugins`）。

## 已装过想升级？→ 用 update skill，别重跑安装

```
说『更新公司套件』 → 触发 yoooni-update-team-tools
```
或直接：
```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\scripts\update-team-tools.ps1"
# = git pull 两个 MCP 仓 + 引擎有变化才重建 + claude plugin marketplace update + claude plugin update <p>@<p>
```

## 常见坑

### `'git' / 'node' / 'claude' 不是内部或外部命令`
对应工具未安装或未加入 PATH。git 必需；node/npm 用于 MCP 构建；claude CLI 用于 MCP 注册 + 插件安装。装好重开终端再跑。

### `git clone` 卡住 / 连不上 Gitee
确认网络可达：`Test-NetConnection -ComputerName gitee.com -Port 443`。需鉴权则配 `git config --global credential.helper manager` 或在 Gitee 配 SSH/Token。

### `claude mcp add` 报 `missing required argument 'commandOrUrl'`
PowerShell 会吞掉裸 `--`，导致变参 `-e` 把 `node` 和路径也吃掉。脚本已用引号包住 `'--'` 规避；手敲时也要写成 `... -e "DOMAIN_KB_DIR=..." '--' node "...\server.js"`。

### `claude plugin update/install` 报 `Plugin ... not found`
插件名必须带 `@marketplace` 全限定，如 `team-standards@team-standards`，不能用裸名。

### `npm run build` 失败
确认 node >=18。删 `node_modules` 重试：`Remove-Item -Recurse -Force node_modules; npm install; npm run build`。

### `/plugin install` 报 `Invalid JSON ... Unrecognized token`
插件仓库的 manifest 带了 BOM。这是**插件仓库侧**问题（见各仓库 CLAUDE.md 的无 BOM 写法），需仓库维护者修复。

## 各工具装好后做什么

- **team-standards**：团队通用开发规范（编码、设计文档强制、Git 提交规范），按 skill 自动触发。
- **project-coding-profiles**：项目级编码画像（GBK/UTF-8 编码守护、模块脚手架），在已登记项目内触发。
- **domain-knowledge**（MCP）：业务公共认知库，AI 遇流程/状态/公式时自助查询。改完知识点用 MCP 工具 `reload_knowledge` 免重启生效。
- **cross-topology**（MCP，复用同一引擎）：跨项目调用链/拓扑库，AI 追跨项目链路时自助查询（search → get_knowledge → get_related）。同样支持 `reload_knowledge`。
