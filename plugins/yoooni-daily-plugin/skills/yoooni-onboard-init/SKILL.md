---
name: yoooni-onboard-init
description: 当用户需要入职初始化、首次拉取 Yoooni 项目文档、执行 SVN checkout 项目文档、或说"我是新同事/怎么开始/初始化环境/拉一下项目文档"时触发。自动检查 SVN 客户端是否安装，首次运行时引导用户填写并保存 SVN 账号密码，后续自动读取，将项目文档 checkout 到本地，完成入职第一步。
---

# Yoooni 入职初始化 Skill

> 🧭 **Yoooni 入职链路**：**① 拉项目文档（本步）** → ② 连内网共享 [yoooni-smb-share-access](../yoooni-smb-share-access/SKILL.md) → ③ 拉源码+搭环境 [yoooni-idea-import](../yoooni-idea-import/SKILL.md) → ④ 日常启动 [yoooni-start](../yoooni-start/SKILL.md)

本 skill 完成新同事入职的**第一步**：通过 SVN 将 Yoooni 项目文档拉取到本地。

**SVN 仓库地址**：`http://47.115.158.133:22/svn/yoooni/Yoooni/项目文档`

账号密码**不硬编码**，保存在用户主目录的配置文件中，首次运行时引导填写。

## 触发条件

用户表达以下任一意图时调用：

- "入职初始化"、"初始化环境"、"我是新同事，怎么开始"
- "拉一下项目文档"、"SVN checkout"、"拉取 Yoooni 文档"
- "第一步做什么"、"怎么配置本地环境"

## 前置检查

按顺序检查，不通过则先解决：

```powershell
# 1. 检查 SVN 客户端是否已安装
svn --version --quiet
```

若命令不存在，提示用户安装（见下"安装 SVN 客户端"章节），**不要跳过继续执行 checkout**。

## 安装 SVN 客户端

### Windows（推荐 SlikSVN，纯命令行，无 GUI 依赖）

1. 访问 [SlikSVN 官网](https://sliksvn.com/download/) 下载安装包
2. 安装后重启终端，确认 `svn --version` 正常输出
3. 或安装 TortoiseSVN（含命令行工具选项）：安装时勾选 **"command line client tools"**

### macOS

```bash
brew install subversion
```

## 执行步骤

### Step 0: 读取或初始化 SVN 账号配置

配置文件路径（存在用户主目录，不在插件目录，插件升级不会覆盖）：
- Windows：`%USERPROFILE%\.config\yoooni\svn-auth.json`
- macOS/Linux：`~/.config/yoooni/svn-auth.json`

**检查配置文件是否存在**：

```powershell
# Windows
$authFile = "$env:USERPROFILE\.config\yoooni\svn-auth.json"
Test-Path $authFile
```

```bash
# macOS
AUTH_FILE="$HOME/.config/yoooni/svn-auth.json"
test -f "$AUTH_FILE" && echo "exists" || echo "missing"
```

**若配置文件不存在（首次运行）**，自动创建目录和模板，然后**暂停执行，请用户填写账号密码**：

```powershell
# Windows — 创建模板
New-Item -ItemType Directory -Force "$env:USERPROFILE\.config\yoooni" | Out-Null
@'
{
  "svn_username": "请填写你的SVN用户名",
  "svn_password": "请填写你的SVN密码"
}
'@ | Set-Content -Encoding UTF8 "$env:USERPROFILE\.config\yoooni\svn-auth.json"
Write-Host "已创建配置模板：$env:USERPROFILE\.config\yoooni\svn-auth.json"
Write-Host "请在编辑器中填写账号密码后，告诉我「填好了」继续。"
```

```bash
# macOS — 创建模板
mkdir -p "$HOME/.config/yoooni"
cat > "$HOME/.config/yoooni/svn-auth.json" <<'EOF'
{
  "svn_username": "请填写你的SVN用户名",
  "svn_password": "请填写你的SVN密码"
}
EOF
echo "已创建配置模板：$HOME/.config/yoooni/svn-auth.json"
echo "请在编辑器中填写账号密码后，告诉我「填好了」继续。"
```

创建模板后**停下来等用户确认**，不要继续执行后续步骤。用户说"填好了"或"继续"后，再进入 Step 1。

**若配置文件已存在**，读取账号密码：

```powershell
# Windows — 读取凭据
$auth = Get-Content -Encoding UTF8 "$env:USERPROFILE\.config\yoooni\svn-auth.json" -Raw | ConvertFrom-Json
$svnUser = $auth.svn_username
$svnPass = $auth.svn_password
Write-Host "已读取账号: $svnUser"
```

```bash
# macOS — 读取凭据（需要 python3 或 jq）
SVN_USER=$(python3 -c "import json,sys; d=json.load(open('$HOME/.config/yoooni/svn-auth.json')); print(d['svn_username'])")
SVN_PASS=$(python3 -c "import json,sys; d=json.load(open('$HOME/.config/yoooni/svn-auth.json')); print(d['svn_password'])")
echo "已读取账号: $SVN_USER"
```

### Step 1: 确认本地目标路径

默认 checkout 到用户主目录下的 `yoooni-docs` 文件夹，询问用户是否使用默认路径或自定义。

```powershell
# Windows 默认路径
$targetPath = "$env:USERPROFILE\yoooni-docs"
if (Test-Path $targetPath) {
    Write-Host "目录已存在: $targetPath"
    Get-ChildItem $targetPath | Select-Object -First 10
} else {
    Write-Host "将 checkout 到: $targetPath"
}
```

### Step 2: SVN Checkout 项目文档

使用 Step 0 读取到的 `$svnUser` / `$svnPass`（或 `$SVN_USER` / `$SVN_PASS`）：

```powershell
# Windows PowerShell
svn checkout "http://47.115.158.133:22/svn/yoooni/Yoooni/项目文档" "$targetPath" `
  --username $svnUser --password $svnPass --no-auth-cache
```

```bash
# macOS / Linux
svn checkout "http://47.115.158.133:22/svn/yoooni/Yoooni/项目文档" "$HOME/yoooni-docs" \
  --username "$SVN_USER" --password "$SVN_PASS" --no-auth-cache
```

`--no-auth-cache` 让 SVN 不再额外存一份密码到系统凭据，统一由配置文件管理。

### Step 3: 验证拉取结果

```powershell
# Windows
Get-ChildItem "$env:USERPROFILE\yoooni-docs" | Format-Table Name, LastWriteTime, Length
```

```bash
# macOS
ls -la "$HOME/yoooni-docs"
```

看到文档目录和文件列表，说明 checkout 成功。

## 后续可选操作

- 打开文档目录：`explorer "$env:USERPROFILE\yoooni-docs"`（Windows）
- 日后更新文档（拉取最新版本）：`svn update "$env:USERPROFILE\yoooni-docs"`
- 修改账号密码：直接编辑 `%USERPROFILE%\.config\yoooni\svn-auth.json`

## 常见坑

### `svn: command not found` / `'svn' 不是内部或外部命令`
SVN 客户端未安装或未加入 PATH。见上方"安装 SVN 客户端"章节。
Windows 装 TortoiseSVN 时记得勾选 **command line client tools**，否则只有 GUI 没有 `svn` 命令。

### `svn: E170013: Unable to connect to a repository`
网络不通，或地址/端口有误。先测试连通性：
```powershell
Test-NetConnection -ComputerName 47.115.158.133 -Port 22
```
若 `TcpTestSucceeded : False`，请确认是否在公司网络/VPN 环境中，或联系管理员确认 SVN 服务状态。

### 中文路径在命令行乱码（Windows）
PowerShell 默认编码可能导致中文 URL 显示异常，但 `svn` 命令本身能正确处理 UTF-8 URL。
若遇到编码问题，可先 `chcp 65001` 切换到 UTF-8 代码页再执行。

### `svn: E215004: Authentication failed`
账号密码不对。编辑 `%USERPROFILE%\.config\yoooni\svn-auth.json` 修正后重试。
若账号已被更改，联系管理员获取新密码。

### 目标路径已存在且非空
`svn checkout` 遇到非空目录会报错。解决方案：
- 选一个空目录或新路径
- 或执行 `svn cleanup` + `svn update` 更新已有的 checkout 副本
