# yoooni-daily-plugin

Yoooni 团队日常工作 Claude Code 插件。包含 **6 个 Skill**，后续按需扩展。

## 快速开始（60 秒）

在 Claude Code 里依次执行：

```
/plugin marketplace add https://gitee.com/wyoooni/yoooni-daily-plugin.git
/plugin install yoooni-daily-plugin@yoooni-daily-plugin
/reload-plugins
```

装好后即可使用。直接说"我是新同事怎么开始"进入入职路线图第一步。

## 🧭 入职路线图（新同事按此顺序走）

```
① 拉项目文档        ② 连内网共享          ③ 拉源码+搭环境           ④ 日常启动
yoooni-onboard-init → yoooni-smb-share-access → yoooni-idea-import   →  yoooni-start
  SVN 拉文档            修 SMB / 访问 \\IT01      Gitee 克隆 + IDEA/Resin     每天起 Redis+Resin
  (先了解项目)          (拿安装包/lib)            + 编译运行(端口 90)         (环境搭好后)
```

- **①→②→③ 是一次性入职搭建**，按顺序做；③ 依赖 ② （安装包/lib 在 `\\IT01`）。
- **④ 是搭好后每天用**的启动流程。
- 直接对 Claude 说对应触发语即可进入某一步（如"我是新同事怎么开始"、"连不上 \\IT01"、"导入 Yoooni 项目"、"启动 Yoooni"）。每个 SKILL 顶部都有链路面包屑可前后跳转。

## Skills 一览

| Skill 名 | 一句话描述 | 触发短语示例 |
|---|---|---|
| [yoooni-onboard-init](skills/yoooni-onboard-init/SKILL.md) | 入职初始化：SVN 拉取项目文档 | "入职初始化"、"拉一下项目文档"、"我是新同事怎么开始" |
| [yoooni-smb-share-access](skills/yoooni-smb-share-access/SKILL.md) | 共享网络访问：修复 SMB，访问 \\IT01 | "连不上共享"、"访问 \\IT01"、"安全策略阻止来宾访问"、"修复 SMB" |
| [yoooni-idea-import](skills/yoooni-idea-import/SKILL.md) | IDEA 导入 Yoooni：搭建 Resin 开发环境 | "导入 Yoooni 项目"、"IDEA 打开 Yoooni"、"配置 Resin"、"项目跑不起来" |
| [yoooni-start](skills/yoooni-start/SKILL.md) | 日常启动：检查中间件(Redis/Oracle)并启动 | "启动 Yoooni"、"跑起来"、"起项目"、"本地起服务" |
| [yoooni-install-team-tools](skills/yoooni-install-team-tools/SKILL.md) | 一键安装公司团队工具（Gitee 源）：2 插件 + 1 MCP + 1 知识库 | "安装公司插件"、"拉一下团队工具"、"一键安装团队规范"、"装 team-standards/MCP" |
| [yoooni-prod-log-query](skills/yoooni-prod-log-query/SKILL.md) | 查生产后台接口注册日志（apiRegistrylog）排查线上 | "查生产日志"、"查接口日志"、"排查线上 XX 接口"、"apiRegistrylog" |

## Skills 详细说明

### yoooni-onboard-init — 入职初始化

**触发短语**：
- "入职初始化" / "初始化环境" / "我是新同事，怎么开始"
- "拉一下项目文档" / "SVN checkout" / "拉取 Yoooni 文档"
- "第一步做什么"

**核心功能**：
- 检查 SVN 客户端是否安装，未安装时给出安装指引
- 执行 `svn checkout` 将项目文档拉取到本地（默认 `~/yoooni-docs`）
- 验证拉取结果，展示文档目录内容

SVN 地址：`http://47.115.158.133:22/svn/yoooni/Yoooni/项目文档`

详见 [skills/yoooni-onboard-init/SKILL.md](skills/yoooni-onboard-init/SKILL.md)

### yoooni-smb-share-access — 共享网络访问（修复 SMB）

**触发短语**：
- 访问 `\\IT01` 时弹"输入网络凭据"、提示用户名或密码不正确
- "连不上共享" / "网络共享打不开" / "共享文件夹无法访问"
- "访问 \\IT01" / "打开 \\IT01\版本更新" / "SMB Guest 访问被禁" / "修复 SMB"

**核心功能**：
- 以管理员运行 `apply_smb_guest_it01.ps1`：导入注册表（开启不安全 Guest 登录、关闭 SMB 签名）→ `Set-SmbClientConfiguration` → 重启 Workstation 服务 → 清旧会话 → 自测并列出共享
- 引导访问 `\\IT01` / `\\IT01\版本更新`，弹凭据框时用 **guest 账号、密码留空**
- 一般无需重启电脑（服务重启即生效）

> ⚠️ 开启不安全 Guest 登录会降低本机 SMB 安全性，仅建议在可信的公司内网使用。

详见 [skills/yoooni-smb-share-access/SKILL.md](skills/yoooni-smb-share-access/SKILL.md)

### yoooni-idea-import — IDEA 导入 Yoooni（搭建 Resin 开发环境）

**触发短语**：
- "导入 Yoooni 项目" / "IDEA 怎么打开 Yoooni" / "搭建 Yoooni 开发环境"
- "配置 Resin" / "resin.xml 怎么配" / "WebRoot/WEB-INF 怎么放"
- "项目跑不起来 / 启动不了"

**核心功能**：
- 源码从 Gitee 克隆：`git clone https://gitee.com/wyoooni/yoooni.git`
- 基于内网共享 `\\IT01\版本更新\安装包\IDEA导入Yoooni项目` 的官方文档，文字化导入流程
- 搭目录结构（WebRoot/WEB-INF/lib）、拷贝 lib 与 IDEA 配置、安装并配置 Resin4、启动调试
- 标注技术栈（Spring + Struts2 + DWR + Druid，JDK 1.8，依赖 Redis）与常见坑

> 前置：先能访问 `\\IT01` 共享（见 yoooni-smb-share-access）；界面步骤对照共享里的官方 PDF 截图。

详见 [skills/yoooni-idea-import/SKILL.md](skills/yoooni-idea-import/SKILL.md)

### yoooni-start — 日常启动（检查中间件并启动）

**触发短语**：
- "启动 Yoooni" / "跑起来" / "起项目" / "本地起服务" / "项目怎么启动"

**核心功能**（与 yoooni-idea-import 的"首次搭建"区分，本 skill 只管日常启动）：
- 检查必备中间件 **Redis**（默认 `127.0.0.1:6379`，取自 `standard.properties`）：没在跑就按默认路径起；默认路径找不到则**提示用户输入 Redis 地址/安装路径**再启动
- 预检远程 **Oracle** 连通性（`jdbc.properties`，远程库无需本机启动）
- 启动 Resin（脚本或 IDEA）→ 访问 `http://localhost:8080/login/login.jsp`

详见 [skills/yoooni-start/SKILL.md](skills/yoooni-start/SKILL.md)

### yoooni-install-team-tools — 一键安装公司团队工具

**触发短语**：
- "安装公司插件" / "拉一下团队工具" / "一键安装团队规范"
- "装 team-standards / project-coding-profiles / project-domain-knowledge / cross-project-topology"
- "新机器配置公司开发规范" / "拉一下公司的 plugin 和 mcp"

**核心功能**（公司当前用 **Gitee** 管理源码，安装地址一律用 Gitee）：
- 一键脚本 `install-team-tools.ps1`：克隆/更新四个仓库（幂等，重复运行安全）
- **2 个插件**（marketplace + install）：team-standards（团队编码规范）、project-coding-profiles（项目编码画像）
- **2 个 MCP 实例，复用同一引擎**：project-domain-knowledge 的 `dist/server.js` 是通用 md+frontmatter 知识引擎，靠 `DOMAIN_KB_DIR` 指向不同知识根目录，注册成两个实例——
  - `domain-knowledge` → 业务公共认知（project-domain-knowledge）
  - `cross-topology` → 跨项目拓扑（cross-project-topology，借同一 server.js，无需自己 build）

| 仓库 | 类型 | Gitee 地址 |
|---|---|---|
| team-standards | 插件 | `https://gitee.com/wyoooni/team-standards.git` |
| project-coding-profiles | 插件 | `https://gitee.com/wyoooni/project-coding-profiles.git` |
| project-domain-knowledge | MCP 引擎 + 业务认知 | `https://gitee.com/wyoooni/project-domain-knowledge.git` |
| cross-project-topology | MCP（复用引擎）跨项目拓扑 | `https://gitee.com/wyoooni/cross-project-topology.git` |

> 插件用 `/plugin` slash 命令安装（脚本无法代敲，需在 Claude Code 会话执行）；两个 MCP 实例与克隆部分由脚本自动完成。cross-topology 需 cross-project-topology 仓库建立 `knowledge/` 知识根目录（frontmatter 含 `id` 的 .md）后才有内容可服务。

详见 [skills/yoooni-install-team-tools/SKILL.md](skills/yoooni-install-team-tools/SKILL.md)

### yoooni-prod-log-query — 生产日志查询（排查线上）

**触发短语**：
- "查生产日志" / "查接口日志" / "看生产后台接口调用记录"
- "排查线上 XX 接口" / "线上这个方法查一下" / "apiRegistrylog"
- "查 url=insertOrUpdatePoconfig 的生产请求"

**核心功能**：
- 通过生产后台 `https://wyoooni.net/sys/apiRegistrylog_list.action` 查接口注册日志
- 表单化参数：日期范围、接口名、url 方法（主过滤条件）、内容、启用状态
- cookie 存用户主目录配置文件 `%USERPROFILE%\.config\yoooni\prod-backend.json`，**不硬编码、不入仓库**
- **cookie 过期自动检测**（返回疑似登录页）→ 退出码 3 并打印替换指引
- 成功后原始 HTML 存 `%TEMP%\yoooni-prod-log\`，可直接 Read 解析日志表格

> ⚠️ 配置文件含登录凭据，仅存本机用户目录，切勿提交到任何仓库。

详见 [skills/yoooni-prod-log-query/SKILL.md](skills/yoooni-prod-log-query/SKILL.md)

## 目录结构

```
yoooni-daily-plugin/
├── .claude-plugin/
│   ├── plugin.json          # 插件主 manifest
│   └── marketplace.json     # 市场分发配置
├── skills/
│   ├── yoooni-onboard-init/   # 入职初始化 skill
│   │   └── SKILL.md
│   ├── yoooni-smb-share-access/ # 共享网络访问 skill（修复 SMB / 访问 IT01）
│   │   ├── SKILL.md
│   │   ├── apply_smb_guest_it01.ps1  # 一键修复脚本（管理员运行）
│   │   └── fix_smb_guest_it01.reg    # 配套注册表
│   ├── yoooni-idea-import/      # IDEA 导入 Yoooni / Resin 环境搭建 skill（首次）
│   │   ├── SKILL.md
│   │   ├── IDEA-手动操作指引.md   # IDEA 图形界面手把手（项目结构/Facet/工件/运行配置）
│   │   ├── start-yoooni.ps1     # 一键启动脚本（Redis + Resin console）
│   │   └── setup-idea-config.ps1 # 一键生成 IDEA 运行配置（encodings/compiler/resin-web）
│   ├── yoooni-start/            # 日常启动 skill（检查中间件并启动）
│   │   └── SKILL.md
│   ├── yoooni-install-team-tools/ # 一键安装公司团队工具 skill（Gitee 源）
│   │   ├── SKILL.md
│   │   └── install-team-tools.ps1 # 一键脚本：clone/pull 四仓库 + 构建注册 MCP
│   └── yoooni-prod-log-query/    # 生产日志查询 skill（接口注册日志排查）
│       ├── SKILL.md
│       └── query-prod-log.ps1   # 查询脚本：表单参数 + cookie 配置 + 过期检测
├── .gitignore
├── CLAUDE.md                # 维护指引
└── README.md
```

## 升级已装插件

```
/plugin marketplace update yoooni-daily-plugin
/plugin install yoooni-daily-plugin@yoooni-daily-plugin
```

重启 Claude Code 生效。
