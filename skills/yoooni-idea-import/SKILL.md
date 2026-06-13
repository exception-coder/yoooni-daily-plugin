---
name: yoooni-idea-import
description: 入职初始化相关——当新同事要把 Yoooni 项目导入 IDEA、搭建本地开发/运行环境，或说"导入 Yoooni 项目"、"IDEA 怎么打开 Yoooni"、"配置 Resin"、"项目跑不起来 / 启动不了"、"搭建 Yoooni 开发环境"、"WebRoot/WEB-INF 怎么放"、"resin.xml 怎么配"时触发。基于内网共享 \\IT01\版本更新\安装包\IDEA导入Yoooni项目 的官方文档，引导完成目录结构搭建、lib/IDEA 配置拷贝、Resin4 安装与配置、启动调试。需先能访问 IT01 共享。
---

# Yoooni 项目导入 IDEA（入职环境搭建）

> 🧭 **Yoooni 入职链路**：① 拉项目文档 [yoooni-onboard-init](../yoooni-onboard-init/SKILL.md) → ② 连内网共享 [yoooni-smb-share-access](../yoooni-smb-share-access/SKILL.md) → **③ 拉源码+搭环境（本步）** → ④ 日常启动 [yoooni-start](../yoooni-start/SKILL.md)

把 Yoooni 项目导入 **IDEA 2022**、配好 **Resin4** 服务器并跑起来。这是新同事入职、能访问代码后的**环境搭建**环节。

## 技术栈 / 关键事实

- 老式 Java Web 项目：**Spring + Spring Security + Struts2 + DWR + Druid 连接池**，Servlet 2.5，包名 `com.maxtile.*`
- **JDK 1.8**（文档示例用 `jdk1.8.0_151`），Servlet 容器是 **Resin4**（不是 Tomcat）
- 启动**依赖 Redis**，必须先把 Redis 跑起来
- 欢迎页 `login/login.jsp`

## 前置条件

1. **能访问内网共享 `\\IT01`**——所有安装包、lib、IDEA 配置、官方文档都在
   `\\IT01\版本更新\安装包\IDEA导入Yoooni项目`。
   访问不了（弹"输入网络凭据"）先用 [yoooni-smb-share-access](../yoooni-smb-share-access/SKILL.md) 修好（guest/空密码）。
2. 已装 **IDEA 2022（Ultimate，要 Web/Spring/Struts2/Resin 支持）**、**JDK 1.8**、**Redis**、**Git**。安装包都在共享 `\\IT01\版本更新\安装包\` 根目录：
   - JDK：`jdk\jdk-8u151-windows-x64.rar`（解压后是 .exe 安装器，运行安装）
   - Redis：`redis.zip`（解压即用，跑 `redis-server.exe`）
   - Resin 服务器：`Resin4.7z`；IDEA Resin 插件：`javaee-appServers-resin-idea.zip`
   - 解 `.rar` / `.7z` 需 7-Zip / WinRAR；机器没有就先装（`winget install 7zip.7zip`）。
3. 已拿到 **Yoooni 源码**——从 Gitee 克隆：
   ```bash
   git clone https://gitee.com/wyoooni/yoooni.git
   ```
   克隆下来的就是项目根（含 `WebRoot` 等）。本流程负责在源码基础上把 IDEA + Resin 的运行骨架配好。
   （项目**文档**另走 SVN，见 [yoooni-onboard-init](../yoooni-onboard-init/SKILL.md)。）

> 📘 **IDEA 图形界面那些手动步骤**（打开工程 / 项目结构 / Facet / 工件 / 运行配置）见配套手册
> **[IDEA-手动操作指引.md](IDEA-手动操作指引.md)** —— 含本次实战踩过的坑（WebRoot vs web、重复部署描述符、GBK 编码、`-XDignore.symbol.file`、为何没 ▶ 按钮、Resin 本地/远程怎么选）。
>
> 📷 官方文档（含 IDEA「项目结构 / Resin 配置」的截图）就在共享里：
> `\\IT01\版本更新\安装包\IDEA导入Yoooni项目\IDEA2022导入Yoooni.pdf`（或同目录 `.md`）。

## 共享目录里有什么

路径：`\\IT01\版本更新\安装包\IDEA导入Yoooni项目\`

| 文件/目录 | 用途 |
|---|---|
| `IDEA2022导入Yoooni.pdf` / `.md` | 官方导入文档（含截图，权威来源） |
| `lib\`（javax.ejb/jms/persistence/resource/servlet/jsp、mail.jar 等） | 项目依赖 jar，需拷到项目 `lib` 与 `WEB-INF\lib` |
| `全部lib可替换.zip` | 完整 lib 包（依赖不全/版本不对时用它整套替换） |
| `IDEA配置基础文件\`（`.idea`、`.classpath`、`.project`、`Yoooni.iml`） | 现成的 IDEA 工程配置，拷到你的项目根目录 |
| `web.xml` | 放到 `WebRoot\WEB-INF\` 下 |
| `Resin4.7z` | Resin4 服务器安装包，解压即用 |
| `YooniResin4.zip` | Resin 虚拟机目录模板（解压到自建的虚拟机目录） |
| `images\` | 文档配图 |

## 操作步骤（按官方文档）

> 路径里凡是写了盘符的（`D:\` / `E:\`），都**按自己电脑实际为准**，没有就创建。

### Step 1: 搭目录结构

> 从 Gitee 克隆下来的 `yoooni` 目录**就是项目根**，下面的"创建"按官方文档保留，**已存在的就跳过、缺的才补**（lib、IDEA 配置、web.xml 一般不在仓库里，需要从共享拷）。

1. 项目根目录 `Yoooni`（即克隆得到的目录；从零搭则手动创建空目录）。
2. 在 `Yoooni\WebRoot` 下创建 `WEB-INF`，把共享里的 `web.xml` 复制到 `WEB-INF\`，并在 `WEB-INF` 下再建一个 `classes` 目录。
3. 把共享 `IDEA导入Yoooni项目\lib` 复制到 `Yoooni\lib`。
4. 再把 `Yoooni\lib` 整个复制一份到 `WEB-INF\lib`（两处 lib 内容要一致）。
5. 把共享 `IDEA配置基础文件` 里的 `.idea` / `.classpath` / `.project` / `Yoooni.iml` 复制到你的 `Yoooni` 项目根目录。

### Step 2: 把源码作为工程导入 IDEA

> ⚠️ 共享给的 `.idea` 往往是**空的**（没有 `modules.xml`），直接 Open 文件夹，IDEA 不一定会自动认 `Yoooni.iml`，很可能当成空白工程。下面分"能自动认"和"没认到要手动配"两种情况。

6. **打开工程**：IDEA → `Open` → 选 `Yoooni` 项目根目录。
   - 弹出"发现 Eclipse / 模块文件，是否导入"之类提示时选 **导入**（它读 `.classpath` / `Yoooni.iml`）。
   - 等右下角索引（indexing）跑完。

7. **确认 SDK + 编码 + 编译参数**（这三项缺一会乱码或编译失败）：
   - File → Project Structure → Project，**SDK 选 JDK 1.8**，Language level = 8。
   - Settings → Editor → File Encodings，**项目编码设为 GBK**（源码以 GBK 为主）。⚠️ 仓库是**混合编码**，约 65 个文件是 UTF-8——别转换文件，改用 `.idea/encodings.xml` 对这些文件做 per-file UTF-8 覆盖（详见"常见坑·中文乱码"）。
   - Settings → Build → Compiler → Java Compiler，"Additional command line parameters" 加 **`-XDignore.symbol.file`**（项目引用了 `com.sun.image.codec.jpeg`、`com.sun.xml.internal.ws` 等 JDK 内部 API，不加这个参数会报"程序包不存在"）。

8. **核对 / 手动配模块结构**（Project Structure → Modules，对照官方 PDF 截图）。若上一步 IDEA 没自动认出来，按下面手动设：
   - **Sources**：把 `src` 标记为 **Sources Root**（蓝色 source 文件夹）。
   - **Paths → Compiler output**：指到 `WebRoot\WEB-INF\classes`。
   - **Dependencies**：新增 **Library**，把整个 `WebRoot\WEB-INF\lib` 目录作为 jar 目录加入（`Yoooni.iml` 用的就是这个 jarDirectory，会自动收下里面所有 jar）。
   - **Facets → Web**：Web 资源目录 = `WebRoot`，部署描述符 = `WebRoot\WEB-INF\web.xml`；项目含 **Spring / Struts2** facet（Ultimate 版才有，识别 `src\config\spring\*`、`src\config\struts\*`）。

   > 实在认不全时，最省事的兜底：`File → New → Module from Existing Sources` 重新指向项目根，按上面四项重配一遍；或直接以 `Yoooni.iml` 为准让 IDEA 加载该模块。

### Step 3: 安装并配置 Resin4

9. **解压 Resin**：用 7-Zip 解 `Resin4.7z`，得到 **Resin 安装目录**（含 `bin` / `lib` / `win64` / `conf\resin.xml`，如 `D:\Resin4\install\Resin4`）。这个目录就是 **resin.home**。
   - `YooniResin4.zip` 解出来只有 `doc` / `log` / `resin-data`，是 Resin 的**数据/工作目录**，不是服务器本体——别拿它当 resin.home。实测用完整安装目录作 resin.home 最省事。
10. **装 Resin 插件**：用共享 `javaee-appServers-resin-idea.zip`（Settings → Plugins → ⚙ → Install Plugin from Disk）。新建 **Resin Run Configuration**，Resin Home 指向上面的安装目录。
11. **改 `resin.xml`**：编辑 `Resin 安装目录\conf\resin.xml`，找到有效的那行 `<web-app id="/" root-directory=...>`（注意文件里可能有别人机器的旧路径如 `H:\...` 和被注释的备用行），把 `root-directory` 指到你的 `WebRoot`，例：
    `D:\yoooni\yoooniCodeSpace\yoooni\WebRoot`。
12. **VM options**（按自己实际路径改，下面是 D 盘示例）：
    ```text
    -Dresin.home=D:\Resin4\install\Resin4 -Djava.library.path="D:\Java\jdk1.8.0_151\bin;D:\Resin4\install\Resin4\win64;D:\Resin4\install\Resin4\bin" -Djava.util.logging.manager=com.caucho.log.LogManagerImpl -Ddruid.logType=log4j
    ```
    > `win64` / `bin` 是 Resin 的**安装目录**下的，不是数据目录——原始文档把两个 `YooniResin4` 混着写，按实际安装目录填。

### Step 4: 启动

**方式 A — IDEA Resin 运行配置**（能装上 Resin 插件时）

13. **先启动 Redis**（如 `D:\redis\redis\redis-server.exe`）。
14. 在 IDEA 里 **Build** 一次（把 `src` 编译到 `WebRoot\WEB-INF\classes`），再点击 **Resin 启动**。
15. 起来后访问 `http://localhost:90/login/login.jsp` 确认可登录。

> ⚠️ **Resin 插件在新版 IDEA（2023.2+）已被官方移除**，Marketplace 里搜到的 `Resin Pura` / `Helsing` 是第三方、非官方。优先用共享 `javaee-appServers-resin-idea.zip` 走「从磁盘安装」；若提示版本不兼容，用下面的方式 B。

**方式 B — 命令行一键脚本**（不依赖 IDEA 插件，最稳，推荐兜底）

本 skill 自带 `start-yoooni.ps1`（与 SKILL.md 同目录）：先起 Redis、同步资源、再用 `java -jar lib\resin.jar -conf conf\resin.xml console` 按 `WebRoot` 启动。把它拷到项目根，改开头路径（ProjDir / RedisDir / ResinHome / JdkHome），然后：

```powershell
powershell -ExecutionPolicy Bypass -File start-yoooni.ps1
```

访问 `http://localhost:90/login/login.jsp`。需要断点调试时，用 IDEA 的 **Remote JVM Debug** 附加到 Resin 进程。

> 🗄️ **数据库（中间件）**：项目用 Spring + Druid + **Oracle**（`oracle.jdbc.OracleDriver`，驱动 `ojdbc14.jar` 已在 lib）。
> 连接配置在 **`src\jdbc.properties`**（`jdbc.url/username/password`），当前生效项连的是**远程共享 Oracle**（如 `jdbc:oracle:thin:@47.106.94.45:1521:orcl`）——**不用在本机装/起 Oracle**，只要网络能连到（多半需公司网络/VPN）。本地唯一要启动的中间件是 **Redis**，`start-yoooni.ps1` 已含 Redis 启动 + Oracle 连通性预检。
> （`oralce11g-64` 安装包只在你想用本地库时才需要，对应 jdbc.properties 里那些 `192.168.x` 的注释项。）

## 常见坑

### 访问 8080 打不开 / 不知道端口
本项目 `resin.xml` 把 HTTP 端口配成了 **90**（不是 Resin 默认 8080），与应用 `standard.properties` 的 `rooturl=http://localhost:90/` 吻合。启动日志会打印 `http listening to *:90`。访问 **`http://localhost:90/login/login.jsp`**。

### 扫描报 `META-INF/versions/9/module-info.class unknown constant pool type`
现代 jar（commons-lang3/codec 等多版本 JAR）里的 Java9 模块描述符，Resin4 老扫描器看不懂——**只是告警，不影响启动**，可忽略。

### 启动报连接失败 / Bean 初始化报错
多半是 **Redis 没启动**。先确认本地 Redis 在跑。

### Spring 报 `class path resource [config/spring/...] cannot be resolved ... does not exist`
`WEB-INF\classes` 里**只有 .class、缺资源文件**（Spring/Struts 的 xml、`*.properties`、ibatis 的 sql_map xml）。
原因：纯 `javac` 只编译不拷资源；**IDEA 的 Build(Ctrl+F9) 会自动把 src 下非 .java 文件拷到 classes**。
对策：在 IDEA Build 一次；或用脚本——`start-yoooni.ps1` 启动前已自动 `robocopy src → WEB-INF\classes /XF *.java` 同步资源。

### `ClassNotFound` / 依赖缺失
`WEB-INF\lib` 与项目 `lib` 没保持一致，或 lib 不全。用共享里的 `全部lib可替换.zip` 整套替换再试。

### Resin 起不来 / 找不到应用
`resin.xml` 的 `web-app root-directory` 没指到 `WebRoot`，或 VM options 里 `-Dresin.home` / `java.library.path` 路径与你电脑实际盘符不符。逐项对照自己的目录改。

### 用 resin.exe 启动后秒退、弹"Windows 功能/正在下载所需的文件"
`resin.exe`（原生启动器）依赖 **.NET Framework 3.5**，Win11 默认没装 → 触发联网下载且 resin.exe 启动即退出（命令行立刻返回、端口不监听、无进程）。
对策：**别用 resin.exe，改用 JDK 直接起**（`start-yoooni.ps1` 已是这种方式）：
```text
java -Dresin.home=<ResinHome> -Djava.library.path=<ResinHome>\win64 -Ddruid.logType=log4j -jar <ResinHome>\lib\resin.jar -conf <ResinHome>\conf\resin.xml console
```
那个 .NET 下载弹窗可直接取消。

### 脚本报"字符串缺少终止符 / 意外的标记"（中文乱码）
`.ps1` 存成 **UTF-8 无 BOM** 时，PowerShell 5.1 按 GBK 读 → 中文串乱码冲断解析。
对策：把脚本存成 **UTF-8 带 BOM**（本 skill 自带的脚本已带 BOM）。

### 编译报错、语言级别不对
项目是 JDK 1.8 + javax.* 老 API，**SDK 必须选 1.8**，用更高 JDK 会因 `javax` 移除/语言级别报错。

### 中文乱码（混合编码：GBK 为主 + 少量 UTF-8）
本仓库是**混合编码**——绝大多数 .java 是 **GBK**，但混进了约 **65 个 UTF-8** 文件（多在 `com/maxtile/application/erp/finance`、`openapi`、`common/utils` 等）。单一项目编码必然让一部分乱码。
> ⚠️ **不要去转换文件编码！** 实测把 UTF-8 文件批量转 GBK 会丢数据、且污染 git（几十上百个文件变更）。
>
> **正确做法（无损、不改源码、不进 git）**：用本 skill 自带的 **`setup-encodings.ps1`** 一条命令生成 `.idea/encodings.xml`（`.idea` 未被 git 跟踪）：
> ```powershell
> powershell -ExecutionPolicy Bypass -File setup-encodings.ps1   # 放项目根运行
> ```
> 它扫描 `src` / `WebRoot`，每棵树按**多数派**定目录默认编码（实测 `src`→GBK、`WebRoot`→UTF-8），**少数派逐文件覆盖**，生成约 700+ 条规则。完事在 IDEA `File → Reload All from Disk`。
>
> 原理（手工等价）：`encodings.xml` 用目录级默认 + 例外覆盖：
> ```xml
> <component name="Encoding" addBOMForNewFiles="with no BOM">
>   <file url="file://$PROJECT_DIR$/src" charset="GBK" />        <!-- src 树默认 GBK -->
>   <file url="file://$PROJECT_DIR$/WebRoot" charset="UTF-8" />  <!-- WebRoot 树默认 UTF-8 -->
>   <file url="file://$PROJECT_DIR$/src/.../XxxUtf8.java" charset="UTF-8" />  <!-- 例外 -->
>   <file url="PROJECT" charset="GBK" />
> </component>
> ```
> 检测某文件编码：严格 UTF-8 解码能过且含非 ASCII 即 UTF-8，否则 GBK。
>
> ⚠️ **背景**：这个混合编码是同事用 UTF-8 存了一批文件（仓库主体是 GBK）造成的。**根治应是团队统一编码**（统一到 UTF-8 最稳，无损），但那是全仓库变更、需团队决策；个人本地用 `setup-encodings.ps1` 即可正常开发。
>
> **编译**：用 **IDEA Build**（按每文件编码分组编译，能处理混合）；命令行单一 `javac -encoding` 处理不了混合编码，只适合临时验证依赖。

### `程序包 com.sun.* / sun.* 不存在`
项目引用了 JDK 内部专有 API（`com.sun.image.codec.jpeg`、`com.sun.xml.internal.ws` 等），JDK 8 的 rt.jar 里有，但默认符号表挡掉了。
对策：IDEA 编译器参数加 **`-XDignore.symbol.file`**（命令行同理）。共享根目录的 `rt.jar` 也是为此准备的备用件。

### 界面步骤拿不准
打开共享里的 `IDEA2022导入Yoooni.pdf` 对照截图操作——那是权威来源，本 skill 是它的文字索引。
