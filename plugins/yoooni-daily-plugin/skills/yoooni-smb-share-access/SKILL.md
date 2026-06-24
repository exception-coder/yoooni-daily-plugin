---
name: yoooni-smb-share-access
description: 当用户访问内网共享 \\IT01（或 \\IT01\版本更新）失败时触发。典型场景：访问时弹"输入网络凭据"提示用户名或密码不正确、"连不上共享"、"网络共享打不开"、"提示组织安全策略阻止未经身份验证的来宾访问"、"SMB 来宾/Guest 访问被禁"、"修复 SMB"。一键以管理员运行 apply_smb_guest_it01.ps1（导入注册表开启不安全 Guest 登录、关闭 SMB 签名、重启 Workstation 服务、清旧会话、自测并列出共享），再引导用 guest 账号空密码访问 \\IT01。一般无需重启电脑。
---

# Yoooni 内网共享 IT01 免密访问处理流程

> 🧭 **Yoooni 入职链路**：① 拉项目文档 [yoooni-onboard-init](../yoooni-onboard-init/SKILL.md) → **② 连内网共享（本步）** → ③ 拉源码+搭环境 [yoooni-idea-import](../yoooni-idea-import/SKILL.md) → ④ 日常启动 [yoooni-start](../yoooni-start/SKILL.md)

适用场景：访问 `\\IT01` 或 `\\IT01\版本更新` 时，Windows 弹出**"输入网络凭据"**，提示用户名或密码不正确。

## 问题原因

这类共享用的是 **SMB Guest（访客）访问**。部分 Windows 机器默认禁止、或不自动使用 Guest 访问旧式/匿名共享，所以会弹账号密码窗口。

本次实际排查结论：

- `IT01` 网络连通正常、SMB 端口正常、**允许 Guest 访问**
- 本机注册表需要**开启 insecure guest logon**（并关闭 SMB 签名强制）
- 访问时若弹凭据框，需在框里选 **`guest` 用户、密码留空**

> IT01 的 IP 为 `192.168.9.253`（主机名解析不了时可用 IP 直连）。

## 注册表/配置改了什么

`fix_smb_guest_it01.reg`（与本 SKILL.md 同目录）在两处写入 SMB 客户端放行项，外加服务端兼容项：

| 位置 | 关键值 | 作用 |
|---|---|---|
| `SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation` | `AllowInsecureGuestAuth=1`、`EnableInsecureGuestLogons=1` | **策略路径**，新版 Windows 上优先级更高，必须有 |
| `SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters` | 同上 + 签名项=0 | 客户端运行时参数 |
| `SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters` | 签名项=0 | 服务端兼容项（影响别人访问本机，与本机访问 IT01 无关，仅为与原文件一致） |

脚本还会调 `Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -RequireSecuritySignature $false -EnableSecuritySignature $false`，与注册表双保险。

> ⚠️ 安全提示：开启不安全 Guest 登录会降低本机 SMB 安全性，仅建议在**可信的公司内网**使用，不要在公共/不可信网络开启。

## 执行步骤

### Step 1: 定位脚本

优先用本 skill 自带的脚本（脚本和 `fix_smb_guest_it01.reg` 必须在同一目录，脚本用 `$PSScriptRoot` 找 reg）：

```powershell
$ps1 = Get-ChildItem "$env:USERPROFILE\.claude\plugins" -Recurse -Filter apply_smb_guest_it01.ps1 -ErrorAction SilentlyContinue |
       Select-Object -First 1 -ExpandProperty FullName
$ps1
```

找不到时，从本插件源码目录里取这两个文件（`apply_smb_guest_it01.ps1` + `fix_smb_guest_it01.reg`）放到同一文件夹即可。

### Step 2: 用管理员 PowerShell 执行

写 `HKEY_LOCAL_MACHINE` 和重启服务都需要管理员。**右键 PowerShell → 以管理员身份运行**，然后：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
& $ps1
```

> 若 `$ps1` 没取到，直接写全路径，例如：
> `& "C:\路径\apply_smb_guest_it01.ps1"`
>
> 脚本不是管理员会自己提示并退出（exit 1）。

脚本自动完成：导入注册表 → 开启 `EnableInsecureGuestLogons` → 关闭 SMB 签名强制 → 重启 Workstation 服务 → 清理旧的 IT01 SMB 会话 → 测试 `\\IT01` → 列出共享目录。

### Step 3: 核对脚本输出

正常应看到客户端配置：

```text
EnableInsecureGuestLogons : True
RequireSecuritySignature  : False
EnableSecuritySignature   : False
```

并能列出共享：

```text
Users
版本更新
```

看到这两组结果即成功。

### Step 4: 访问共享 \\IT01

在资源管理器地址栏输入，或 **Win + R** 输入：

```text
\\IT01
```

或直接：

```text
\\IT01\版本更新
```

**如果仍弹"输入网络凭据"，不要输个人账号**，按下面填：

```text
用户名：guest
密码：留空
```

然后确定即可进入。

## 是否需要重启电脑

**一般不需要。** 脚本已重启 Workstation 服务让 SMB 设置重新读取，通常立即生效。仅当服务重启后仍异常时，再重启一次电脑（重启前先提示用户保存工作、征得同意）。

## 常见坑

### 弹框输了个人账号又失败
这类共享只认 Guest。清掉错误连接后用 guest/空密码重来：

```powershell
net use \\IT01 /delete
# 再到资源管理器输 \\IT01，凭据框填 guest / 空密码
```

### 提示"凭据冲突 / 多重连接"（System error 1219）
本机已存在到 IT01 的其他连接（不同账号）。脚本已尝试清 `IPC$`，若仍报错手动清：

```powershell
net use \\IT01 /delete
net use \\192.168.9.253 /delete
net use * /delete /y   # 慎用：清掉所有已映射的网络连接
```

### `net view \\IT01` 或解析失败
主机名解析不到或不在同一网络。确认是否连了公司内网 / VPN；用 IP 直连试 `\\192.168.9.253`；必要时在 `hosts` 里加 `192.168.9.253  IT01`，或联系 IT。

### 改完开机又被刷回
公司域控可能用**组策略**强制覆盖这些项。联系 IT 在域策略层放开。

### 想撤销改动（恢复更安全的默认）
关掉不安全 Guest 登录：

```powershell
Set-SmbClientConfiguration -EnableInsecureGuestLogons $false -Force
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" /v EnableInsecureGuestLogons /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" /v AllowInsecureGuestAuth /f
```
