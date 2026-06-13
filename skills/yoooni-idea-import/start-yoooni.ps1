# 一键启动 Yoooni 本地环境：先起 Redis，再用 java -jar resin.jar console 按 conf\resin.xml 部署 WebRoot 启动。
# 不依赖 IDEA Resin 插件，也不用 resin.exe（resin.exe 依赖 .NET 3.5）——新版 IDEA(2023.2+)官方 Resin 插件已移除时的稳妥跑法。
# 用法：右键"用 PowerShell 运行"，或：  powershell -ExecutionPolicy Bypass -File start-yoooni.ps1
# 启动后浏览器访问： http://localhost:90/login/login.jsp
# 调试：用 IDEA 的 Remote JVM Debug 附加到 Resin 进程。

# ===== 按自己电脑改这几行 =====
$ProjDir   = $PSScriptRoot            # 脚本放在项目根目录，自动取；否则填工程绝对路径
$RedisDir  = "D:\redis\redis"
$ResinHome = "D:\Resin4\install\Resin4"
$JdkHome   = "D:\Java\jdk1.8.0_151"
# 远程 Oracle（来自 src\jdbc.properties 的 jdbc.url，仅做连通性预检，不在本机启动）
$DbHost    = "47.106.94.45"
$DbPort    = 1521
# =============================

$ErrorActionPreference = "Stop"
$env:JAVA_HOME = $JdkHome

# 0) 数据库连通性预检（远程 Oracle，连不上 Resin 会一堆 Bean 报错）
$dbOk = (Test-NetConnection -ComputerName $DbHost -Port $DbPort -WarningAction SilentlyContinue).TcpTestSucceeded
if ($dbOk) {
    Write-Host "[Oracle] $DbHost`:$DbPort 可达" -ForegroundColor Green
} else {
    Write-Host "[Oracle] $DbHost`:$DbPort 连不上！确认在公司网络/VPN、或 jdbc.properties 配置 —— Resin 仍会启动但应用初始化大概率失败" -ForegroundColor Yellow
}

# 1) Redis：已在跑(6379 应答 PONG)就跳过，否则新开窗口启动
$redisCli = Join-Path $RedisDir "redis-cli.exe"
$pong = ""
try { $pong = & $redisCli ping 2>$null } catch {}
if ($pong -eq "PONG") {
    Write-Host "[Redis] 已在运行" -ForegroundColor Green
} else {
    Start-Process -FilePath (Join-Path $RedisDir "redis-server.exe") -WorkingDirectory $RedisDir
    Start-Sleep -Seconds 1
    Write-Host "[Redis] 已启动" -ForegroundColor Green
}

# 1.5) 资源同步 + 编译产物检查
#      WEB-INF\classes 要同时有 .class(编译产物) + 资源(xml/properties)。
#      IDEA 的 Build 会自动拷资源；纯 javac 只编译不拷，导致 Spring 找不到 classpath:config/spring/...
$classes = Join-Path $ProjDir "WebRoot\WEB-INF\classes"
if (-not (Get-ChildItem $classes -Recurse -Filter *.class -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    Write-Host "[Build] WEB-INF\classes 没有 .class！先在 IDEA 里 Build Project(Ctrl+F9) 编译，再跑本脚本。" -ForegroundColor Yellow
}
Write-Host "[Build] 同步 src 资源(xml/properties 等) 到 WEB-INF\classes ..." -ForegroundColor DarkGray
robocopy (Join-Path $ProjDir "src") $classes /S /XF *.java /NFL /NDL /NJH /NJS /NP | Out-Null

# 2) Resin：用 JDK 的 java -jar resin.jar console 前台启动
#    （不用 resin.exe——它依赖 .NET Framework 3.5，Win11 默认没装会触发联网下载且启动失败）
$java      = Join-Path $JdkHome "bin\java.exe"
$resinJar  = Join-Path $ResinHome "lib\resin.jar"
$resinConf = Join-Path $ResinHome "conf\resin.xml"
if (-not (Test-Path $java))      { throw "找不到 java: $java（检查 JdkHome）" }
if (-not (Test-Path $resinJar))  { throw "找不到 resin.jar: $resinJar（检查 ResinHome）" }
if (-not (Test-Path $resinConf)) { throw "找不到 resin.xml: $resinConf" }
Write-Host "[Resin] 启动中(java -jar resin.jar console)... 访问 http://localhost:90/login/login.jsp" -ForegroundColor Cyan
& $java "-Dresin.home=$ResinHome" "-Djava.library.path=$ResinHome\win64" "-Ddruid.logType=log4j" -jar $resinJar -conf $resinConf console
