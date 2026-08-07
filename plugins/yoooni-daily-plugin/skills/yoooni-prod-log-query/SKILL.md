---
name: yoooni-prod-log-query
description: 查询 Yoooni 生产后台 apiRegistrylog。用户要求按接口、URL、方法或日期查看生产调用记录、排查线上接口问题时使用。
---

# Yoooni 生产日志查询 Skill

通过生产后台的**接口注册日志**页面（`apiRegistrylog_list.action`）排查线上接口调用情况。
对应页面：`https://wyoooni.net/sys/apiRegistrylog_list.action`。

认证方式：脚本用配置文件里的**账号密码**自动登录（Spring Security `/j_spring_security_check`）拿会话，
**不再需要手工复制 cookie，也不会遇到 cookie 过期**。账号密码**仅存本机用户目录、不入仓库**。

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

账号密码存在配置文件（用户主目录，插件升级不覆盖）：
- Windows：`%USERPROFILE%\.config\yoooni\prod-backend.json`

首次运行脚本会自动创建模板并退出（exit 2），提示填账号密码。引导用户：

1. 打开配置文件 `%USERPROFILE%\.config\yoooni\prod-backend.json`
2. 把 `username` / `password` 填成生产后台 `https://wyoooni.net` 的**登录账号和密码**
3. 告诉我「填好了」再继续

> 配置示例：
> ```json
> {
>   "base_url": "https://wyoooni.net",
>   "username": "你的登录账号",
>   "password": "你的登录密码"
> }
> ```

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
  - 不带 `-AllPages`：第 1 页原始 HTML 存 `%TEMP%\yoooni-prod-log\apilog_<时间>.html`，并打印总记录/总页数
  - 带 `-AllPages`：翻页合并后的 HTML 存 `%TEMP%\yoooni-prod-log\apilog_all_<时间>.html`（仅含去重数据行，便于一次 Read 解析全部）
- `2` 账号密码未配置/未填 → 引导用户填账号密码（Step 1）
- `3` **登录失败**（账号密码错误/被锁，或会话被并发登录挤掉）→ 见下方
- `1` 请求失败（网络不通等）

### Step 4：解析结果

查询成功后，**直接 Read 脚本打印的 HTML 文件**解析日志表格（接口、url、内容、时间、状态等），按用户排查目的总结；或让用户在浏览器打开核对。

> 数据行里的业务字段在 **Body / Result** 列的 JSON 里（如 `makedate` 制单时间、`checkdate` 审核时间、`proid` 货品 id、`code` 单号）。时间是**毫秒时间戳**，换算用 UTC+8。

## 登录失败怎么办（exit 3）

1. 用浏览器登录 `https://wyoooni.net` 验证账号密码能否正常进后台
2. 若密码改了，更新配置文件 `%USERPROFILE%\.config\yoooni\prod-backend.json` 的 `password`
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
配置文件含登录账号密码，**仅存本机用户目录、不要提交到任何仓库**（`.config/yoooni/` 不在插件仓库内）。
