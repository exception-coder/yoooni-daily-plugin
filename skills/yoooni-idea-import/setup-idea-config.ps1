# 一键生成 / 调整 Yoooni 在 IDEA 下运行相关的配置文件（不改源码、不进 git，.idea 未被跟踪）。
# 写三样：
#   1) .idea\encodings.xml          —— 混合编码映射(src 多为 GBK、WebRoot 多为 UTF-8 + 少数例外)，治中文乱码
#   2) .idea\compiler.xml           —— 构建堆 3072 + 并行编译 + 字节码目标 1.8，加速并避免 GC 抖动
#   3) WebRoot\WEB-INF\resin-web.xml —— JSP 用 -source/-target 1.8 编译，消除"源值 1.5 已过时"告警乱码
# 用法：放项目根 → powershell -ExecutionPolicy Bypass -File setup-idea-config.ps1
# 完事在 IDEA：File -> Reload All from Disk（compiler 堆大小需重启 IDEA、resin-web 需重启 Resin 生效）。
# 注意：SDK=1.8 / 模块输出=WebRoot\WEB-INF\classes / Web facet=WebRoot 等需在 IDEA 图形界面设，见 IDEA-手动操作指引.md。

$ProjDir = $PSScriptRoot          # 脚本在项目根；否则填工程绝对路径
$ErrorActionPreference = "Stop"
$noBom = New-Object System.Text.UTF8Encoding($false)   # XML 必须无 BOM
function Write-Xml($path, $text){
  $dir = Split-Path $path -Parent
  if(-not (Test-Path $dir)){ New-Item -ItemType Directory -Force $dir | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n","`r`n"), $noBom)
}

# ============ 1) .idea\encodings.xml（混合编码） ============
$utf8Strict = New-Object System.Text.UTF8Encoding($false,$true)
$exts = @('*.java','*.xml','*.properties','*.jsp','*.sql','*.js','*.html','*.htm')
function Get-Rel($full){ "file://`$PROJECT_DIR`$/" + ($full.Substring($ProjDir.Length+1) -replace '\\','/') }
$dirDefaults = @(); $overrides = @(); $projDefault = 'GBK'
foreach($rootName in @('src','WebRoot')){
  $rootPath = Join-Path $ProjDir $rootName
  if(-not (Test-Path $rootPath)){ continue }
  $utf8 = New-Object System.Collections.Generic.List[string]
  $gbk  = New-Object System.Collections.Generic.List[string]
  Get-ChildItem $rootPath -Recurse -Include $exts -File -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_.FullName
    if($p -match '\\WEB-INF\\lib\\' -or $p -match '\\WEB-INF\\classes\\'){ return }
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $hasHi = $false; foreach($b in $bytes){ if($b -gt 127){ $hasHi=$true; break } }
    if(-not $hasHi){ return }
    try { [void]$utf8Strict.GetString($bytes); $utf8.Add($p) } catch { $gbk.Add($p) }
  }
  if($utf8.Count -ge $gbk.Count){ $def='UTF-8'; $exc=$gbk; $excEnc='GBK' }
  else { $def='GBK'; $exc=$utf8; $excEnc='UTF-8' }
  $dirDefaults += "    <file url=`"file://`$PROJECT_DIR`$/$rootName`" charset=`"$def`" />"
  foreach($f in $exc){ $overrides += "    <file url=`"$(Get-Rel $f)`" charset=`"$excEnc`" />" }
  if($rootName -eq 'src'){ $projDefault = $def }
  Write-Host "[encodings] $rootName -> 默认 $def，例外 $($exc.Count) 个($excEnc)" -ForegroundColor Cyan
}
$encLines = @('<?xml version="1.0" encoding="UTF-8"?>','<project version="4">','  <component name="Encoding" addBOMForNewFiles="with no BOM">')
$encLines += $dirDefaults + $overrides + "    <file url=`"PROJECT`" charset=`"$projDefault`" />" + @('  </component>','</project>')
Write-Xml (Join-Path $ProjDir ".idea\encodings.xml") ($encLines -join "`r`n")

# ============ 2) .idea\compiler.xml（构建堆 + 并行 + 字节码 1.8） ============
$compilerXml = @'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="CompilerConfiguration">
    <option name="BUILD_PROCESS_HEAP_SIZE" value="3072" />
    <bytecodeTargetLevel target="1.8" />
  </component>
  <component name="CompilerWorkspaceConfiguration">
    <option name="PARALLEL_COMPILATION" value="true" />
  </component>
</project>
'@
Write-Xml (Join-Path $ProjDir ".idea\compiler.xml") $compilerXml
Write-Host "[compiler] 构建堆 3072 + 并行编译 + 字节码 1.8" -ForegroundColor Cyan

# ============ 3) WebRoot\WEB-INF\resin-web.xml（JSP 用 1.8 编译） ============
$resinWeb = @'
<?xml version="1.0" encoding="UTF-8"?>
<!-- 让 Resin 编译 JSP 时用 1.8，消除"源值 1.5 已过时"告警乱码。仅消除告警，不影响功能。 -->
<web-app xmlns="http://caucho.com/ns/resin">
  <javac args="-source 1.8 -target 1.8" />
</web-app>
'@
Write-Xml (Join-Path $ProjDir "WebRoot\WEB-INF\resin-web.xml") $resinWeb
Write-Host "[resin-web] JSP 编译 -source/-target 1.8" -ForegroundColor Cyan

Write-Host "`n完成。下一步：IDEA `File -> Reload All from Disk`；compiler 堆大小需重启 IDEA、resin-web 需重启 Resin 生效。" -ForegroundColor Green
Write-Host "SDK=1.8 / 模块输出=WebRoot\WEB-INF\classes / Web facet=WebRoot 等图形界面设置见 IDEA-手动操作指引.md。" -ForegroundColor Yellow
