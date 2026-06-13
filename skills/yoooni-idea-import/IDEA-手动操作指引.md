# IDEA 导入 Yoooni — 手动操作指引（图形界面手把手）

> 本文是 [SKILL.md](SKILL.md) 的配套手册，专门讲 **IDEA 里必须手动点的步骤**（这些没法脚本化）。
> 命令行能自动做的部分（克隆、搭 WEB-INF/lib、装 JDK/Redis/Resin）见 SKILL.md。
> 路径示例用本次实战的真实路径，**按你自己电脑改盘符**：
> - 工程：`D:\yoooni\yoooniCodeSpace\yoooni`
> - JDK：`D:\Java\jdk1.8.0_151`
> - Resin 安装：`D:\Resin4\install\Resin4`
> - Redis：`D:\redis\redis`

## 0. 前置（已就绪才往下）

- 已 `git clone https://gitee.com/wyoooni/yoooni.git`，且 `WebRoot\WEB-INF` 下已有 `web.xml` / `classes` / `lib`(jar 齐全)。
- 已装 **IDEA Ultimate**、**JDK 1.8**、**Redis**、**Resin4**（解压完成）。

---

## 1. 打开工程

`File → Open` → 选工程根目录 `yoooni` → 等索引跑完。

> ⚠️ 共享给的 `.idea` 往往是空的，IDEA 不一定自动认出模块结构，下面的项目结构多半要**手动核对/配置一遍**。

---

## 2. 项目结构（File → Project Structure）

### 2.1 项目（Project）
- **SDK** 选 **JDK 1.8**（`D:\Java\jdk1.8.0_151`）
- **语言级别** = 8

### 2.2 模块（Modules）
- **Sources**：把 `src` 标记为 **Sources Root**
- **Paths → 编译输出**：`WebRoot\WEB-INF\classes`
- **Dependencies**：新增 Library，把整个 `WebRoot\WEB-INF\lib` 目录作为 **jar 目录**加入（`Yoooni.iml` 用的就是这个 jarDirectory，自动收下里面所有 jar）

### 2.3 Facet → Web ⭐最容易错
IDEA 默认会把 Web 根猜成 `web`，**但本项目的 Web 根是 `WebRoot`**（`web` 是空壳）。三处都要指到 `WebRoot`：

| 项 | 正确值 |
|---|---|
| **部署描述符**（只留**一条**） | `...\yoooni\WebRoot\WEB-INF\web.xml` |
| **Web 资源目录** | `...\yoooni\WebRoot` → 相对部署根 `/` |
| **源根** | `...\yoooni\src`（勾选） |

- 若出现**多条部署描述符**（如指向 `web\WEB-INF\web.xml`、`web\web\WEB-INF\web.xml`）：**全删掉，只加一条**指向 `WebRoot\WEB-INF\web.xml`。
- 配好后把多余的空 `web` 目录删掉，免得反复被认错。

### 2.4 工件（Artifacts）
- 类型选 **Web 应用程序：展开型（exploded）**
- 输出布局里有 `WEB-INF` + `'yoooni' 模块: 'Web' facet resources` 即可（facet resources = 整棵 WebRoot，含已编译 classes 和 126 个 jar）
- 右侧"可用元素"里的 **`lib`（项目库）不要拖进去** —— jar 已物理存在于 `WebRoot\WEB-INF\lib`，再加会重复
- 建议勾 **「包含在项目构建中」**，或在运行配置里设"启动前 Build Artifact"

### 2.5 编码 + 编译参数 ⭐否则乱码/编译失败
- `Settings → 编辑器 → 文件编码`：**项目编码设 GBK**（源码以 GBK 为主）。⚠️ 仓库**混合编码**（同事用 UTF-8 存过一批文件）：`src` 多为 GBK、`WebRoot` 多为 UTF-8，还有数百例外。**别转换文件**（丢数据+污染 git）。
  最省事：跑本 skill 自带的 **`setup-encodings.ps1`**（放项目根 → `powershell -ExecutionPolicy Bypass -File setup-encodings.ps1`），它自动生成 `.idea/encodings.xml`（目录级默认 + 逐文件例外），完事 `File → Reload All from Disk`。
- `Settings → 构建、执行、部署 → Java 编译器`："附加命令行参数"加 **`-XDignore.symbol.file`**（项目引用了 `com.sun.image.codec.jpeg`、`com.sun.xml.internal.ws` 等 JDK 内部 API，不加会报"程序包不存在"）

---

## 3. 运行配置（关键：没有它就没有 ▶ 按钮）

> 项目结构配好 ≠ 有运行配置。右上角 ▶ 灰着，就是因为**还没建运行配置**，这个老项目也不会自动生成。

### 方式 A：原生 Resin 运行配置（推荐，带热部署/调试）
前提：已装 Resin 插件（共享 `javaee-appServers-resin-idea.zip` 走 ⚙ → 从磁盘安装；新版 IDEA 官方 Resin 插件已移除，Marketplace 的 `Resin Pura`/`Helsing` 是第三方）。

`运行 → 编辑配置 → + → Resin → 本地`
- **本地 vs 远程**：选 **本地**（在本机启动/部署/管理 Resin）；远程是连别的机器上已跑的 Resin，本地开发用不到。
- 列表里出现**两个 Resin**=装了两个 Resin 插件，随便选一个的「本地」即可。
- 表单：
  - **Application server** → 注册 Resin，指向 `D:\Resin4\install\Resin4`
  - **部署** 标签 → + → 工件 → `yoooni:Web exploded`
  - **VM 选项**：
    ```text
    -Dresin.home=D:\Resin4\install\Resin4 -Djava.library.path="D:\Java\jdk1.8.0_151\bin;D:\Resin4\install\Resin4\win64;D:\Resin4\install\Resin4\bin" -Djava.util.logging.manager=com.caucho.log.LogManagerImpl -Ddruid.logType=log4j
    ```
  - **URL**：`http://localhost:90/`

### 方式 B：Shell Script 运行配置跑脚本（不折腾插件，也能要绿色 ▶）
`运行 → 编辑配置 → + → Shell Script` → 执行选 **Script text**：
```
powershell -ExecutionPolicy Bypass -File "D:\yoooni\yoooniCodeSpace\yoooni\start-yoooni.ps1"
```

### 方式 C：直接终端跑脚本（最快，无需任何运行配置）
IDEA 底部 **终端**：
```powershell
powershell -ExecutionPolicy Bypass -File .\start-yoooni.ps1
```

---

## 4. 启动顺序

1. **先起 Redis**（`D:\redis\redis\redis-server.exe`；方式 B/C 的脚本会自动起）
2. 方式 A：点 ▶；方式 B/C：跑脚本
3. 浏览器访问 **`http://localhost:90/login/login.jsp`**

> 🗄️ **数据库（中间件）**：Spring + Druid + **Oracle**（驱动 `ojdbc14.jar` 已在 lib）。连接配置在 **`src\jdbc.properties`**，当前生效项连**远程共享 Oracle**（如 `@47.106.94.45:1521:orcl`）——**不用本机装/起 Oracle**，只要网络能连到（多半需公司网络/VPN）。本地唯一要起的中间件是 **Redis**（`start-yoooni.ps1` 已含启动 + Oracle 连通性预检）。

---

## 5. 构建加速（首次全量编译很慢，实测有效）

首次 `Rebuild Project` 慢（7000+ 文件 + 拷资源 + 工件 + 字节码增强，混合编码还要分组编译，可能十几分钟）。**这是一次性的**，之后用 `Build Project (Ctrl+F9)` 是**增量**，几秒钟。再加几招提速：

1. **关 / 排除 Windows Defender 实时扫描**（⭐ 提升最明显）：Defender 会逐个扫描新写出的 `.class`，极拖慢。把工程目录、JDK、Resin 目录加入"排除项"（设置 → 隐私和安全性 → 病毒和威胁防护 → 管理设置 → 排除项），或临时关实时防护。**实测快非常多。**
2. **调大构建堆 + 并行编译**：本 skill 已在项目 `.idea/compiler.xml` 写好：
   ```xml
   <component name="CompilerConfiguration">
     <option name="BUILD_PROCESS_HEAP_SIZE" value="3072" />   <!-- 默认 700 偏小 -->
     <bytecodeTargetLevel target="1.8" />
   </component>
   <component name="CompilerWorkspaceConfiguration">
     <option name="PARALLEL_COMPILATION" value="true" />
   </component>
   ```
   等价 UI：`Settings → 构建/执行/部署 → 编译器`，"共享构建进程堆大小"=3072、勾"独立模块并行编译"。改完**重启 IDEA**（堆大小下次构建生效）。
3. **平时别用 Rebuild**：改完代码 `Ctrl+F9` 增量构建即可；**只跑应用**时 Resin 运行配置/`start-yoooni.ps1` 会增量构建工件，不必全量 Rebuild。

> 注：混合编码（src=GBK、WebRoot=UTF-8）会让编译器按编码分组、比单一编码慢一点——根治是全仓库统一编码（需团队决策）。

---

## 6. 常见坑速查

| 现象 | 原因 / 解决 |
|---|---|
| 右上角没有 ▶ 按钮 | 没建运行配置 → 第 3 节 |
| 编辑配置里没有 Resin | Resin 插件没装/没重启 → 从磁盘装共享 zip |
| 部署标签没有可选工件 | 工件没建 → 2.4 创建 Web exploded |
| 中文乱码（混合编码） | 项目编码 GBK + 用 `.idea/encodings.xml` 给 ~65 个 UTF-8 文件做 per-file 覆盖（2.5）；**别转文件**（丢数据+污染git） |
| `程序包 com.sun.* / sun.* 不存在` | 编译器参数加 `-XDignore.symbol.file`（2.5） |
| Resin 起不来/找不到应用 | Web 根指成了 `web` 而非 `WebRoot`（2.3）；或 VM options 盘符不对 |
| `resin.exe` 秒退、弹"Windows 功能下载" | resin.exe 依赖 .NET 3.5（Win11 没装）→ 改用 `java -jar lib\resin.jar console`（脚本已是此方式），下载弹窗取消即可 |
| `.ps1` 报"字符串缺少终止符/意外标记" | 脚本存成了 UTF-8 无 BOM，PS 5.1 按 GBK 读乱 → 存成 **UTF-8 带 BOM** |
| 访问 8080 打不开 | 本项目 resin.xml 端口配的是 **90**（日志 `http listening to *:90`）→ 访问 `http://localhost:90/...` |
| 扫描报 `module-info.class unknown constant pool` | 现代 jar 的多版本 JAR，Resin4 扫描器看不懂，**仅告警不影响启动**，忽略 |
| 启动报连接失败 / Bean 初始化错 | Redis 没起；或数据库没配（第 4 节） |
| Spring 报 `config/spring/... cannot be resolved` | classes 里缺资源(xml/properties)；IDEA Build(Ctrl+F9) 会自动拷资源，或脚本已自动同步 |
| 首次 Build 巨慢(十几分钟) | 一次性全量；关 Windows Defender 实时扫描 + 调大构建堆/并行编译（第 5 节）；之后用增量 Ctrl+F9 |
| 界面步骤拿不准 | 对照共享 `IDEA2022导入Yoooni.pdf` 截图 |
