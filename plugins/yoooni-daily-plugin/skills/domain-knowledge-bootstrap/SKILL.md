---
name: domain-knowledge-bootstrap
description: 为业务项目初始化或补齐业务真理知识库。用户要求 domain-knowledge-bootstrap、起草业务真理、按模块扫描并生成 draft，或初始化项目画像与 domain knowledge 时触发。兼容 Claude Code、Codex 与 Cursor，并将执行转交给 project-domain-knowledge 仓库中的唯一规范正文。
---

# Domain Knowledge Bootstrap（Codex / Claude 分发入口）

本文件只负责让插件宿主发现技能；流程的唯一规范正文仍由
`project-domain-knowledge/.claude/skills/domain-knowledge-bootstrap/SKILL.md` 维护，禁止在这里复制第二套流程。

## 执行步骤

1. 定位 `project-domain-knowledge` 权威仓库：
   - 当前仓库名为 `project-domain-knowledge` 时直接使用当前仓库；
   - 否则优先读取 `~/.kai-toolbox/workspace.path`，以其内容为团队工具根目录，再拼接 `project-domain-knowledge`；
   - Windows 默认安装位置为 `%USERPROFILE%\.kai-toolbox\team-tools\project-domain-knowledge`。
2. 完整读取权威仓库中的 `.claude/skills/domain-knowledge-bootstrap/SKILL.md`。
3. 严格按该正文执行；其中 Agent 入口规则为：Claude Code 使用 `CLAUDE.md`，Codex / Cursor 使用 `AGENTS.md`，多工具项目同步维护两份。
4. 若权威正文不存在，停止写入并提示用户先安装或更新 `project-domain-knowledge`，不要凭记忆重建流程。

## 边界

- 本入口不改变知识库目录、稳定性审批、人工确认或 MCP reload 规则。
- 不因 Codex 适配而把 `draft` 自动升级为 `stable`。
- 不用符号链接代替 `AGENTS.md` / `CLAUDE.md`，也不生成只有跳转文字的空壳入口。
