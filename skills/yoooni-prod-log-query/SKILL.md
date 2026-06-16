---
name: yoooni-prod-log-query
description: 查询 Yoooni 生产后台「接口注册日志」(apiRegistrylog) 排查线上问题。当用户说"查生产日志"、"查接口日志"、"排查线上接口"、"看看生产后台某接口的调用记录"、"apiRegistrylog"、"查某个方法/url 的生产请求"、"线上这个接口报错查一下"时触发。通过生产后台 https://wyoooni.net/sys/apiRegistrylog_list.action 按日期/接口名/url方法/内容/启用状态过滤查询。cookie 存用户主目录配置文件，过期会自动检测并提示替换后重查。
---

# Yoooni 生产日志查询 Skill

通过生产后台的**接口注册日志**页面（`apiRegistrylog_list.action`）排查线上接口调用情况。
对应页面：`https://wyoooni.net/sys/apiRegistrylog_list.action`。

cookie **不硬编码**，存用户主目录配置文件；**过期会自动检测并提示替换**。

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

> 最常用的是 `-Url`（要排查的接口方法名）+ 日期范围。其余留空即查全部。

## 执行步骤

### Step 1：确认/初始化 cookie

cookie 存在配置文件（用户主目录，插件升级不覆盖）：
- Windows：`%USERPROFILE%\.config\yoooni\prod-backend.json`

首次运行脚本会自动创建模板并退出（exit 2），提示填 cookie。引导用户：

1. 浏览器登录 `https://wyoooni.net`
2. F12 开发者工具 → Network → 任意一个请求 → 复制 Request Headers 里**整段 cookie 值**
   （形如 `JSESSIONID=xxx; rmbUser=true; userName=xxx; passWord=xxx`）
3. 粘贴到配置文件的 `cookie` 字段
4. 告诉我「填好了」再继续

### Step 2：向用户确认查询条件

至少确认**要排查的接口方法名（`-Url`）和日期范围**。用户没指定日期就用默认（近 3 天）。

### Step 3：执行查询

```powershell
# 最常用：查某接口方法近 3 天
powershell -ExecutionPolicy Bypass -File "<plugin>\skills\yoooni-prod-log-query\query-prod-log.ps1" -Url insertOrUpdatePoconfig

# 指定日期范围 + 多条件
powershell -ExecutionPolicy Bypass -File ".\query-prod-log.ps1" `
  -StartDate 2026-06-13 -EndDate 2026-06-16 -Url insertOrUpdatePoconfig -ApiName "" -Content "" -Enable ""
```

脚本退出码：
- `0` 成功，原始 HTML 存到 `%TEMP%\yoooni-prod-log\apilog_<时间>.html`，并打印行数概要
- `2` cookie 未配置/未填 → 引导用户填 cookie（Step 1）
- `3` **cookie 过期/未登录** → 提示用户按下方流程替换 cookie 后重查
- `1` 请求失败（网络不通等）

### Step 4：解析结果

查询成功后，**直接 Read 脚本打印的 HTML 文件**解析日志表格（接口、url、内容、时间、状态等），按用户排查目的总结；或让用户在浏览器打开核对。

## cookie 过期怎么办（exit 3）

脚本检测到返回页面不像日志列表（疑似跳登录页）时，会打印替换指引并退出 3。照做：

1. 浏览器重新登录 `https://wyoooni.net`
2. F12 → Network → 复制最新整段 cookie
3. 覆盖配置文件 `%USERPROFILE%\.config\yoooni\prod-backend.json` 的 `cookie` 字段
4. 重新执行 Step 3

> 过期时脚本也会把返回内容存成 `expired_<时间>.html`，便于确认是不是登录页。

## 常见坑

### 一直返回登录页 / 反复 exit 3
- cookie 复制不全（要整段，含 `JSESSIONID`）。
- 账号在别处重新登录导致旧会话失效——重新复制最新 cookie。

### 请求失败 / 连不上（exit 1）
确认在公司网络、`https://wyoooni.net` 可达：
```powershell
Test-NetConnection -ComputerName wyoooni.net -Port 443
```

### 结果为空但 cookie 正常
放宽条件：扩大日期范围、清空 `-Url`/`-ApiName` 再查；确认接口方法名拼写与后台一致。

### 安全提示
配置文件含登录凭据，**仅存本机用户目录、不要提交到任何仓库**（`.config/yoooni/` 不在插件仓库内）。
