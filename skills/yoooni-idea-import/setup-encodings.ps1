# 生成 .idea\encodings.xml 解决"混合编码"乱码：仓库里 .java 多为 GBK，但同事用 UTF-8 存过一批文件，
# 加上 WebRoot 的 jsp/js 多为 UTF-8 —— 单一项目编码必然让一部分乱码。
# 本脚本扫描 src / WebRoot，每棵树按"多数派"定默认编码，"少数派"逐文件覆盖，写进 .idea\encodings.xml。
# 不修改任何源文件、不进 git（.idea 未被跟踪）。生成后在 IDEA 里 File → Reload All from Disk。
# 用法：把脚本放项目根，右键用 PowerShell 运行，或：powershell -ExecutionPolicy Bypass -File setup-encodings.ps1

$ProjDir = $PSScriptRoot          # 脚本在项目根；否则改成工程绝对路径
$roots   = @('src','WebRoot')     # 要处理的源码树
$exts    = @('*.java','*.xml','*.properties','*.jsp','*.sql','*.js','*.html','*.htm')

$ErrorActionPreference = "Stop"
$utf8Strict = New-Object System.Text.UTF8Encoding($false,$true)

function Get-Rel($full){ "file://`$PROJECT_DIR`$/" + ($full.Substring($ProjDir.Length+1) -replace '\\','/') }

$dirDefaults = @()      # 目录级默认行
$overrides   = @()      # 例外行
$projDefault = 'GBK'    # 项目级默认（src/WebRoot 之外的文件）

foreach($rootName in $roots){
  $rootPath = Join-Path $ProjDir $rootName
  if(-not (Test-Path $rootPath)){ continue }
  $utf8 = New-Object System.Collections.Generic.List[string]
  $gbk  = New-Object System.Collections.Generic.List[string]
  Get-ChildItem $rootPath -Recurse -Include $exts -File -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_.FullName
    if($p -match '\\WEB-INF\\lib\\' -or $p -match '\\WEB-INF\\classes\\'){ return }  # 跳过 jar 和编译输出
    $bytes = [System.IO.File]::ReadAllBytes($p)
    $hasHi = $false; foreach($b in $bytes){ if($b -gt 127){ $hasHi=$true; break } }
    if(-not $hasHi){ return }   # 纯 ASCII，编码无关
    try { [void]$utf8Strict.GetString($bytes); $utf8.Add($p) } catch { $gbk.Add($p) }
  }
  # 多数派作目录默认，少数派逐文件覆盖
  if($utf8.Count -ge $gbk.Count){
    $def='UTF-8'; $exc=$gbk; $excEnc='GBK'
  } else {
    $def='GBK';   $exc=$utf8; $excEnc='UTF-8'
  }
  $dirDefaults += "    <file url=`"file://`$PROJECT_DIR`$/$rootName`" charset=`"$def`" />"
  foreach($f in $exc){ $overrides += "    <file url=`"$(Get-Rel $f)`" charset=`"$excEnc`" />" }
  if($rootName -eq 'src'){ $projDefault = $def }
  Write-Host "[$rootName] UTF-8=$($utf8.Count) GBK=$($gbk.Count) -> 默认 $def，例外 $($exc.Count) 个($excEnc)" -ForegroundColor Cyan
}

$lines = @('<?xml version="1.0" encoding="UTF-8"?>','<project version="4">','  <component name="Encoding" addBOMForNewFiles="with no BOM">')
$lines += $dirDefaults
$lines += $overrides
$lines += "    <file url=`"PROJECT`" charset=`"$projDefault`" />"
$lines += @('  </component>','</project>')

$ideaDir = Join-Path $ProjDir ".idea"
if(-not (Test-Path $ideaDir)){ New-Item -ItemType Directory -Force $ideaDir | Out-Null }
$xml = Join-Path $ideaDir "encodings.xml"
[System.IO.File]::WriteAllText($xml, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "已生成: $xml  (项目默认 $projDefault，共 $(($dirDefaults.Count + $overrides.Count + 1)) 条)" -ForegroundColor Green
Write-Host "下一步：在 IDEA 里 File -> Reload All from Disk（或重启 IDEA）。" -ForegroundColor Yellow
