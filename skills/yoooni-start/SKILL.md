---
name: yoooni-start
description: 日常启动 Yoooni 项目（已搭好环境后每天用）。当用户说"启动 Yoooni / 跑起来 / 起项目 / 本地起服务 / 启动开发环境 / start yoooni / 项目怎么启动"时触发。先确定项目根目录（读已保存配置 / 默认 D:\yoooni\yoooniCodeSpace\yoooni / 找不到就问用户并记住，绝不在磁盘乱搜 start-yoooni.ps1），再检查本地必备中间件 Redis（默认 127.0.0.1:6379，没在跑就按默认路径启动；找不到 redis-server 时问用户），预检远程 Oracle 连通性，最后用绝对路径跑项目根的 start-yoooni.ps1 启动 Resin（无需 cd 到项目目录）并给出访问地址。与首次环境搭建的 yoooni-idea-import 区分——本 skill 只管"启动"，不重复搭建。
---

# Yoooni 日常启动

> 🧭 **Yoooni 入职链路**：① 拉项目文档 [yoooni-onboard-init](../yoooni-onboard-init/SKILL.md) → ② 连内网共享 [yoooni-smb-share-access](../yoooni-smb-share-access/SKILL.md) → ③ 拉源码+搭环境 [yoooni-idea-import](../yoooni-idea-import/SKILL.md) → **④ 日常启动（本步，每天用）**

环境**已搭好**后的每日启动流程：检查本地依赖 → 起 Redis → 预检数据库 → 起 Resin → 访问。

> 还没搭过环境（没克隆源码 / 没装 JDK·Redis·Resin / IDEA 没导入）？先走 [yoooni-idea-import](../yoooni-idea-import/SKILL.md)，本 skill 只负责"启动"。

## 依赖与默认地址（来自项目配置，按需调整）

| 依赖 | 默认地址 / 路径 | 来源 | 是否本地启动 |
|---|---|---|---|
| **Redis**（必备） | `127.0.0.1:6379`；安装 `D:\redis\redis` | 应用 `src\standard.properties`（serverIp/serverPort） | ✅ 本地起 |
| **Oracle**（必备） | 远程 `47.106.94.45:1521:orcl` | `src\jdbc.properties`（jdbc.url 当前生效项） | ❌ 远程，不本机起，只需连通 |
| Resin | `D:\Resin4\install\Resin4` | 环境搭建时确定 | 启动应用 |
| JDK | `D:\Java\jdk1.8.0_151` | 环境搭建时确定 | — |
| 访问入口 | `http://localhost:90/login/login.jsp` | resin.xml 配的是 **90** 端口(非默认8080)，与应用 `rooturl=localhost:90` 吻合 | — |

## 启动流程

### Step 0: 确定项目根目录（别靠当前目录、别乱搜）

⚠️ **不要在文件系统里搜 `start-yoooni.ps1`**（会找错目录、卡很久）。也**无需让用户 cd 到项目目录**——后面全用绝对路径。按下面取项目根：

```powershell
# 读已保存的项目根；没有则用默认
$cfg = "$env:USERPROFILE\.config\yoooni\project.json"
$proj = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).project_root } else { "D:\yoooni\yoooniCodeSpace\yoooni" }
"项目根: $proj   start-yoooni.ps1 存在? " + (Test-Path (Join-Path $proj "start-yoooni.ps1"))
```

- **存在** → 用这个 `$proj`，进入 Step 1。
- **不存在** → **暂停问用户**："你的 Yoooni 项目克隆在哪？（例如 `D:\yoooni\yoooniCodeSpace\yoooni`）"。拿到后存起来，下次自动用：
  ```powershell
  New-Item -ItemType Directory -Force "$env:USERPROFILE\.config\yoooni" | Out-Null
  @{ project_root = "用户给的路径" } | ConvertTo-Json | Set-Content "$env:USERPROFILE\.config\yoooni\project.json" -Encoding UTF8
  ```

### Step 1: 检查 Redis（必备）—— 没有就问用户

**先输出默认地址给用户**（默认就是 IDEA 脚本/应用配置里的本地地址），再检测：

```powershell
$redisIp   = "127.0.0.1"
$redisPort = 6379
$redisDir  = "D:\redis\redis"   # 默认安装路径
Write-Host "Redis 默认地址: $redisIp`:$redisPort，默认安装: $redisDir"

# 1) 已在跑？
$pong = ""
try { $pong = & (Join-Path $redisDir "redis-cli.exe") -h $redisIp -p $redisPort ping 2>$null } catch {}
if ($pong -ne "PONG") {
  $alive = (Test-NetConnection -ComputerName $redisIp -Port $redisPort -WarningAction SilentlyContinue).TcpTestSucceeded
} else { $alive = $true }
"Redis 在跑? " + $alive
```

按结果分支：

- **已在跑** → 跳到 Step 2。
- **没在跑、但默认路径有 `redis-server.exe`** → 直接启动：
  ```powershell
  Start-Process (Join-Path $redisDir "redis-server.exe") -WorkingDirectory $redisDir
  ```
- **没在跑、默认路径也找不到 `redis-server.exe`** → **暂停，提示用户输入 Redis 安装目录或地址**，例如：
  > 「默认路径 `D:\redis\redis` 没找到 redis-server，也没检测到 `127.0.0.1:6379` 上的 Redis。请告诉我你的 Redis 安装目录（或已在运行的 Redis 地址）。」
  
  拿到用户给的路径/地址后再启动或改连，再继续。**Redis 是必备，未就绪不要往下走。**

### Step 2: 预检 Oracle 连通（远程，必备）

```powershell
$dbHost = "47.106.94.45"; $dbPort = 1521
$dbOk = (Test-NetConnection -ComputerName $dbHost -Port $dbPort -WarningAction SilentlyContinue).TcpTestSucceeded
"Oracle $dbHost`:$dbPort 可达? " + $dbOk
```

连不上 → 提示用户：确认在公司网络/VPN，或检查 `src\jdbc.properties` 的 `jdbc.url`（远程库不需本机启动，只需网络可达）。

### Step 3: 启动 Resin

二选一：

- **脚本（最快、推荐）**：**用绝对路径**跑项目根的 `start-yoooni.ps1`（已封装"Redis 预检+启动 / Oracle 预检 / 资源同步 / Resin console 启动"）。下面自包含、不依赖当前目录：
  ```powershell
  $cfg = "$env:USERPROFILE\.config\yoooni\project.json"
  $proj = if (Test-Path $cfg) { (Get-Content $cfg -Raw | ConvertFrom-Json).project_root } else { "D:\yoooni\yoooniCodeSpace\yoooni" }
  powershell -ExecutionPolicy Bypass -File "$proj\start-yoooni.ps1"
  ```
  > console 前台启动会一直占着窗口输出日志，看到 `Resin started ... http listening to *:90` 即成功。
- **IDEA**：点已配好的 Resin 运行配置 ▶（见 [yoooni-idea-import](../yoooni-idea-import/SKILL.md) 的手动指引）。

### Step 4: 验证

浏览器访问 **`http://localhost:90/login/login.jsp`**，能出登录页即启动成功。

## 常见坑

- **登录页打不开 / Bean 初始化报错**：Redis 没起（回 Step 1），或 Oracle 连不上（Step 2）。
- **Redis 端口被占**：`netstat -ano | findstr 6379` 看是不是已有实例；有就别重复起。
- **改了 Redis/数据库地址**：应用 Redis 地址在 `src\standard.properties`，Oracle 在 `src\jdbc.properties`，改完重启 Resin。
