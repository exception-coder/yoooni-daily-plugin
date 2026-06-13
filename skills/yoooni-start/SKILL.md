---
name: yoooni-start
description: 日常启动 Yoooni 项目（已搭好环境后每天用）。当用户说"启动 Yoooni / 跑起来 / 起项目 / 本地起服务 / 启动开发环境 / start yoooni / 项目怎么启动"时触发。先检查本地必备中间件 Redis（默认 127.0.0.1:6379），没在跑就按默认路径启动；默认路径找不到 redis-server 时暂停、提示用户输入 Redis 地址/安装路径再启动；并预检远程 Oracle 连通性，最后启动 Resin 并给出访问地址。与首次环境搭建的 yoooni-idea-import 区分——本 skill 只管"启动"，不重复搭建。
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

- **脚本**（最快）：项目根的 `start-yoooni.ps1` 已封装"Redis 预检+启动 / Oracle 预检 / Resin console 启动"：
  ```powershell
  powershell -ExecutionPolicy Bypass -File start-yoooni.ps1
  ```
- **IDEA**：点已配好的 Resin 运行配置 ▶（见 [yoooni-idea-import](../yoooni-idea-import/SKILL.md) 的手动指引）。

### Step 4: 验证

浏览器访问 **`http://localhost:90/login/login.jsp`**，能出登录页即启动成功。

## 常见坑

- **登录页打不开 / Bean 初始化报错**：Redis 没起（回 Step 1），或 Oracle 连不上（Step 2）。
- **Redis 端口被占**：`netstat -ano | findstr 6379` 看是不是已有实例；有就别重复起。
- **改了 Redis/数据库地址**：应用 Redis 地址在 `src\standard.properties`，Oracle 在 `src\jdbc.properties`，改完重启 Resin。
