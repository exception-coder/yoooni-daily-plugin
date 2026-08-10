---
name: yoooni-prod-log-query
description: 查询 Yoooni 生产后台 apiRegistrylog。用户要求按接口、URL、方法或日期查看生产调用记录、排查线上接口问题时使用。
---

# Yoooni 生产日志查询 Skill

通过生产后台的**接口注册日志**页面（`apiRegistrylog_list.action`）排查线上接口调用情况。
对应页面：`https://wyoooni.net/sys/apiRegistrylog_list.action`。

认证方式：脚本用配置文件里的账号和 **Windows DPAPI(CurrentUser) 加密密码**自动登录
（Spring Security `/j_spring_security_check`）拿会话，**不再需要手工复制 cookie**。
密文只能由录入凭据的同一 Windows 用户解密，配置仅存本机用户目录、不入仓库。

## 触发条件

- "查生产日志"、"查接口日志"、"看生产后台接口调用记录"
- "排查线上 XX 接口"、"线上这个方法查一下"、"apiRegistrylog"
- "查 url=insertOrUpdatePoconfig 的生产请求"

## 查询参数（表单字段）

向用户确认要查什么，映射到后台表单字段：

| 参数 | 表单字段 | 含义 | 默认 |
|---|---|---|---|
| `-StartDate` | `obj.startmakedate` | 制单日期起 `yyyy-MM-dd` | 3 天前 |
| `-EndDate` | `obj.endmakedate` | 制单日期止 `yyyy-MM-dd` | 今天 |
| `-ApiName` | `obj.apiname` | 接口名 | 空 |
| `-Url` | `obj.url` | **接口方法名（主过滤条件）**，如 `insertOrUpdatePoconfig` | 空 |
| `-Content` | `obj.content` | 内容关键词 | 空 |
| `-Enable` | `obj.enable` | 启用状态 | 空 |
| `-AllPages` | — | 开关：**自动翻页抓全部**（默认只取第 1 页 20 条） | 关 |
| `-MaxPages` | — | `-AllPages` 时最多翻几页（防呆上限） | 50 |

> 最常用的是 `-Url`（要排查的接口方法名）+ 日期范围。其余留空即查全部。
> **后台分页每页只有 20 条**——要统计/找某条特定记录时务必加 `-AllPages`，否则只看到最新一页会漏数据。

## 执行步骤

### Step 1：确认/初始化账号密码

凭据配置存在用户主目录，插件升级不覆盖：
- Windows：`%USERPROFILE%\.config\yoooni\prod-backend.json`

首次运行脚本会自动创建不含明文密码的模板并退出（exit 2）。引导用户运行：

```powershell
powershell -ExecutionPolicy Bypass -File "<plugin>\skills\yoooni-prod-log-query\query-prod-log.ps1" -SetCredential
```

脚本交互读取账号与密码（密码不回显），随后只保存 DPAPI 密文：

> ```json
> {
>   "base_url": "https://wyoooni.net",
>   "username": "你的登录账号",
>   "password_protected": "AQAAANCM..."
> }
> ```

旧版配置若仍含 `password` 明文，下一次查询会先成功加密、再原位移除明文字段；迁移失败则停止生产请求。

### Step 2：向用户确认查询条件

至少确认**要排查的接口方法名（`-Url`）和日期范围**。用户没指定日期就用默认（近 3 天）。
若要统计或定位特定单据，提醒用户/自己加 `-AllPages`（否则只有第 1 页 20 条）。

### Step 3：执行查询

```powershell
# 最常用：查某接口方法近 3 天（仅第 1 页）
powershell -ExecutionPolicy Bypass -File "<plugin>\skills\yoooni-prod-log-query\query-prod-log.ps1" -Url insertOrUpdatePoconfig

# 指定日期范围 + 翻全部页（推荐用于统计/找特定记录）
powershell -ExecutionPolicy Bypass -File ".\query-prod-log.ps1" `
  -StartDate 2026-06-13 -EndDate 2026-06-16 -Url insertOrUpdatePoconfig -AllPages
```

脚本退出码：
- `0` 成功
  - 不带 `-AllPages`：第 1 页脱敏 HTML 存 `%TEMP%\yoooni-prod-log\apilog_<时间>.html`
  - 带 `-AllPages`：翻页合并后的脱敏 HTML 存 `%TEMP%\yoooni-prod-log\apilog_all_<时间>.html`
  - 输出默认保留 3 天，可用 `-RetentionDays 1..30` 调整
- `2` 凭据未配置、无法解密或迁移失败 → 用 `-SetCredential` 重新录入（Step 1）
- `3` **登录失败**（账号密码错误/被锁，或会话被并发登录挤掉）→ 见下方
- `1` 请求失败（网络不通等）

### Step 4：解析结果

查询成功后，**直接 Read 脚本打印的脱敏 HTML 文件**解析日志表格（接口、url、内容、时间、状态等），按用户排查目的总结；或让用户在浏览器打开核对。脚本会屏蔽常见令牌、密码、Cookie、邮箱和手机号，但仍应按生产数据处理，不要复制到外部服务。

> 数据行里的业务字段在 **Body / Result** 列的 JSON 里（如 `makedate` 制单时间、`checkdate` 审核时间、`proid` 货品 id、`code` 单号）。时间是**毫秒时间戳**，换算用 UTC+8。

## 登录失败怎么办（exit 3）

1. 用浏览器登录 `https://wyoooni.net` 验证账号密码能否正常进后台
2. 若密码改了，重新运行脚本并加 `-SetCredential`
3. 重新执行 Step 3

> 极少数情况下，账号在别处重新登录会把本会话挤掉——重跑一次脚本即可（每次跑都会重新登录拿新会话）。

## 常见坑

### 登录失败 / 反复 exit 3
- 配置文件里账号密码填错（用浏览器登一次核对）。
- 账号被锁或停用——找管理员。

### 请求失败 / 连不上（exit 1）
确认在公司网络、`https://wyoooni.net` 可达：
```powershell
Test-NetConnection -ComputerName wyoooni.net -Port 443
```

### 结果"看起来少" / 找不到某条记录
后台**每页只有 20 条**，默认只取第 1 页。加 `-AllPages` 翻全部页再找；也可放宽日期范围、清空 `-Url`/`-ApiName`。

### 结果为空
确认接口方法名拼写与后台一致（`-Url`）；扩大日期范围。

### 安全提示
配置文件只保存 DPAPI 密文并收紧为当前用户 ACL。不要提交配置或脱敏日志到任何仓库；脚本只接受无自定义端口、无路径的 `https://wyoooni.net`，避免凭据被错误发送到其它站点。维护者可用 `-SelfTest` 在不访问生产网络的情况下验证 DPAPI、明文迁移、脱敏、ACL、域名和保留期。
