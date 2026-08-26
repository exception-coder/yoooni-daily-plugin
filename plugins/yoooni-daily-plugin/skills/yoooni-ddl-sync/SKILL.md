---
name: yoooni-ddl-sync
description: 安全刷新、检查或定期同步 Yoooni Oracle Schema 的权威 DDL 基线。用户要求 dump/刷新 DDL、检查 Schema 漂移、配置 DDL 定时任务、查看 DDL 快照状态，或询问 Graphify 与真实数据库结构如何保持同步时使用。
---

# Yoooni DDL 快照同步

使用本目录的确定性脚本从真实 Oracle Schema 生成候选快照，通过完整性门禁后再更新 `project-domain-knowledge/knowledge/yoooni/impl/ddl-baseline.md`。

## 核心边界

- Oracle Schema 是权威源；DDL 文件是可审计快照；Graphify 是派生索引，不能反向覆盖 DDL。
- 只读取元数据，不执行 DDL 或 DML。
- 密码只以 Windows DPAPI CurrentUser 密文存于用户配置，不进入仓库、命令行或日志。
- 不自动 commit 或 push。同步成功后必须向用户展示 Git diff 摘要并等待人工审阅。
- 只有用户明确要求周期和时间时才注册计划任务；不得因插件安装或更新擅自创建。

## 操作入口

脚本路径均相对于本 Skill 目录。

```powershell
# 首次配置或密码变更；密码交互输入且不回显
powershell -ExecutionPolicy Bypass -File .\sync-yoooni-ddl.ps1 -Mode SetCredential `
  -ProjectRoot "D:\yoooni\yoooniCodeSpace\yoooni" `
  -KnowledgeRepoRoot "C:\Users\zhang\.kai-toolbox\team-tools\project-domain-knowledge"

# 只检查漂移，不改文件；exit 10 表示发现变化
powershell -ExecutionPolicy Bypass -File .\sync-yoooni-ddl.ps1 -Mode Check

# 验证并发布变化；无变化不写盘
powershell -ExecutionPolicy Bypass -File .\sync-yoooni-ddl.ps1 -Mode Sync

# 离线自测，不访问数据库
powershell -ExecutionPolicy Bypass -File .\sync-yoooni-ddl.ps1 -Mode SelfTest
```

合法批量删表触发缩量门禁时，必须先核对数据库变更单，再由用户明确同意使用 `-AllowShrink`。

## 计划任务

先成功人工执行一次 `Sync`，再根据用户指定的星期和时间注册：

```powershell
powershell -ExecutionPolicy Bypass -File .\register-ddl-sync-task.ps1 `
  -Action Register -Day SUN -At 03:00

powershell -ExecutionPolicy Bypass -File .\register-ddl-sync-task.ps1 -Action Status
powershell -ExecutionPolicy Bypass -File .\register-ddl-sync-task.ps1 -Action Disable
powershell -ExecutionPolicy Bypass -File .\register-ddl-sync-task.ps1 -Action Remove
```

任务只能以录入 DPAPI 凭据的当前用户、Interactive logon token 运行，不得改为 SYSTEM。默认建议每周低峰执行；如果 Schema 迁移频繁，优先在迁移发布流程后显式触发，而不是盲目提高轮询频率。

## 结果处理

| 退出码 | 含义 | 后续动作 |
|---|---|---|
| `0` | 成功、无变化或配置完成 | 查看输出状态 |
| `2` | 配置或凭据缺失 | 运行 `SetCredential` |
| `3` | Java、驱动或路径前置条件失败 | 修复本地依赖 |
| `4` | Oracle 连接或元数据导出失败 | 保留旧基线，检查网络和账号权限 |
| `5` | 完整性或缩量门禁失败 | 人工核对，不得绕过 |
| `10` | Check 模式发现 Schema 漂移 | 审阅后运行 Sync |
| `11` | 已有同步任务运行 | 等待当前任务结束 |

同步成功后读取本地日志路径，运行知识库健康检查，并展示 `project-domain-knowledge` 的 `git diff --stat` 与目标文件 diff；不要自动提交。
