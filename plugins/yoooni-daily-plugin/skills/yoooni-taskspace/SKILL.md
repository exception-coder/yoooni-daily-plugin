---
name: yoooni-taskspace
description: 创建跨目录任务空间，把多个项目目录聚合到一个新工作区。当用户说"创建任务空间"、"合并几个项目"、"几个大目录下的项目放到一个工作区"、"一键选择创建软链接"、"taskspace"、"junction 聚合工作区"时触发。使用本 skill 自带的 taskspace.mjs，在 Windows 上创建 junction，在 macOS/Linux 上创建目录 symlink；支持 create/list/add/remove/teardown，拆除时只删除链接和清单，不删除源项目。
---

# 跨目录任务空间 Skill

把散落在多个大目录下的项目，聚合成一个可见的任务工作区。工作区里每个项目都是链接：

- Windows：目录 junction，无需管理员权限。
- macOS/Linux：目录 symlink。
- 清单文件：`.taskspace.json` 记录成员，可复现、可查看、可安全拆除。

## 触发条件

- "创建任务空间"、"合并几个项目到一个工作区"
- "几个大目录下的项目归到一个新任务空间"
- "一键选择创建软链接"、"用 junction 聚合项目"
- "taskspace create/list/add/remove/teardown"

## 核心原则

1. **不移动源项目**：只在任务空间目录里创建链接。
2. **拆除只删链接**：`teardown` 会先检查 `.taskspace.json`，再逐个删除链接；不会递归删除源目录。
3. **目录非空不强删**：工作区里如果有真实文件，只拆链接并保留目录。
4. **同一次搜索避免重复根**：如果把任务空间作为 cwd，就不要同时把源项目的大父目录也纳入同一次全量扫描，避免重复结果。

## 前置检查

需要 Node.js：

```powershell
node --version
```

本 skill 自带脚本：

```powershell
<plugin>\skills\yoooni-taskspace\taskspace.mjs
```

如果是在本仓库源码内调试，路径通常是：

```powershell
D:\Users\zhang\myWork\yoooni-daily-plugin\skills\yoooni-taskspace\taskspace.mjs
```

## 常用操作

### 交互选择某个父目录下的项目

适合"从一个大目录里勾几个项目"：

```powershell
node "<plugin>\skills\yoooni-taskspace\taskspace.mjs" create --pick D:\bigdir
```

脚本会列出 `D:\bigdir` 下的子目录，输入序号多选；随后提示输入工作区名称。默认工作区会创建在 `D:\` 下，也就是 `--pick` 父目录的上一级。若要指定工作区父目录，补 `--base`：

```powershell
node "<plugin>\skills\yoooni-taskspace\taskspace.mjs" create --pick D:\bigdir --base D:\workspaces
```

### 直接指定多个项目

适合项目来自多个大目录：

```powershell
node "<plugin>\skills\yoooni-taskspace\taskspace.mjs" create --base D:\workspaces --name 任务A --members D:\A\proj1 D:\B\proj2 D:\C\proj3
```

生成：

```text
D:\workspaces\任务A\
├── .taskspace.json
├── proj1 -> D:\A\proj1
├── proj2 -> D:\B\proj2
└── proj3 -> D:\C\proj3
```

之后可以把 `D:\workspaces\任务A` 作为 Claude Code 的 cwd，或在会话里切到这个目录工作。

## 维护命令

查看成员：

```powershell
node "<plugin>\skills\yoooni-taskspace\taskspace.mjs" list D:\workspaces\任务A
```

追加项目：

```powershell
node "<plugin>\skills\yoooni-taskspace\taskspace.mjs" add D:\workspaces\任务A D:\D\proj4
```

移除某个链接：

```powershell
node "<plugin>\skills\yoooni-taskspace\taskspace.mjs" remove D:\workspaces\任务A proj4
```

拆除整个任务空间：

```powershell
node "<plugin>\skills\yoooni-taskspace\taskspace.mjs" teardown D:\workspaces\任务A
```

## 执行时的交互策略

当用户只描述需求但没有给路径时，最多问三个问题：

1. 项目来源：一个父目录下选择，还是多个明确路径？
2. 任务空间放到哪里，例如 `D:\workspaces`。
3. 任务空间名称。

当用户已经给出路径和名称时，直接运行命令并验证：

```powershell
node "<script>" list "<workspace>"
```

如果用户只是想让当前 Claude Code 会话临时看到多个目录，提醒可以优先用 `/add-dir <路径>`。需要持久、可见、可复现的聚合视图时，再使用本 taskspace。
