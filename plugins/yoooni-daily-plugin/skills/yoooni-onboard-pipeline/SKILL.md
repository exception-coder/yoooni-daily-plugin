---
name: yoooni-onboard-pipeline
description: 新项目一键初始化流水线——拉项目→项目画像/CLAUDE.md→业务知识图谱→编码profile→前后端聚合→跨项目拓扑,把公司这套 onboarding 作业编排成一条可断点续跑的流水线。当用户说"初始化新项目"、"一键 onboard"、"接入一个新系统"、"把某项目拉起来建知识图谱和规范"、"项目初始化流水线"、"工作台初始化作业"时触发。编排已有能力(domain-knowledge-bootstrap / project-coding-profiles / yoooni-taskspace),机械步骤自动跑,需判断的节点设人工关卡,不做无人值守黑盒。
---

# 新项目初始化流水线 Skill

把公司「接入一个新项目」的全套作业编排成一条流水线:**拉项目 → 画像/CLAUDE.md → 业务知识图谱 → 编码 profile → 前后端聚合 → 跨项目拓扑**。

**定位**:编排器,不是黑盒。机械步骤(clone/聚合/建骨架)自动跑;需判断的节点(模块切分、技术栈、stable 与否、集成关系)停下来让人/AI 决策。复用已有能力,不重造。

## 触发条件

- "初始化新项目" / "一键 onboard" / "接入一个新系统"
- "把某项目拉起来,建知识图谱和编码规范"
- "项目初始化流水线" / "工作台初始化作业"

## 红线

- ❌ 不无人值守全自动入库——业务真理走人工关卡,产出经评审才升 stable(见 domain-knowledge-bootstrap)。
- ❌ 不在本流水线重写知识抽取/profile 逻辑——一律调用下层已有 skill。
- ✅ 幂等可续跑:每阶段状态记在 `~/.kai-toolbox/onboard-<系统>.json`,中断后可接着跑。

## 前置

- 在能访问目标项目代码的机器上;若要做知识图谱/profile,需能访问
  `project-domain-knowledge` 与 `project-coding-profiles` 两个仓库(团队工具已装,见 yoooni-install-team-tools)。
- 本 skill 自带编排脚本:`<plugin>/skills/yoooni-onboard-pipeline/pipeline.mjs`。

## 编排脚本(机械胶水)

```
node pipeline.mjs plan --repos <路径或url>... [--name <系统>] [--ws <工作区父目录>]
   探测每个仓角色(前端/后端/微服务)、判前后端分离、产出六阶段计划 + 状态文件
node pipeline.mjs mark --name <系统> --stage <id> [--status done|skipped]
   标记某阶段完成(每过一道关卡就 mark)
node pipeline.mjs aggregate --name <系统> --members <路径>...
   调 yoooni-taskspace 建前后端聚合工作区
node pipeline.mjs status --name <系统>
   看进度
```

阶段 id:`fetch / profile / knowledge / coding / aggregate / topology`。

<!-- APPEND_FLOW -->

## 六阶段执行流程

被触发时,先 `plan` 出计划念给用户确认范围,再逐阶段推进。每阶段:做事 → 过关卡(让用户拍板) → `mark` 标记。

### ① fetch — 拉取/定位项目 [自动]

- 用户给本地路径就直接用;给 git url 则 clone 到工作区目录(已存在跳过)。
- `plan` 会探测每个仓角色与栈。**关卡**:跟用户确认哪个是后端/前端、是否同属一个系统。
- 完成 → `mark --stage fetch`。

### ② profile(画像)— 项目画像 + CLAUDE.md [AI起草+人确认]

- AI 读顶层/包结构/配置/构建文件,识别技术栈、分层、**编码(GBK?UTF-8?)**、启动方式。
- 前后端分离 → **每个仓各写一份自包含的 `CLAUDE.md` 且互相指向**;不要只写一份。
- **关卡**:技术栈识别对不对、编码判定对不对(GBK 项目要警示乱码,UTF-8 不必)。
- 完成 → `mark --stage profile`。

### ③ knowledge — 业务知识图谱 [人判定，调 domain-knowledge-bootstrap]

- **调用 `domain-knowledge-bootstrap` skill**(在 project-domain-knowledge 仓库),不在这里重写。
- 流程:建 `knowledge/<project>/impl/modules.json`(模块→代码映射)→ `scan` 扫代码面 →
  **人判边界**(哪些是业务真理)→ `new` 生成骨架 → 填口径 → `check` + `catalog`。
- 优先用 **DDL/SQL 脚本**里的状态字典等作可信来源(比类名推断准,可直接 stable);
  纯推断的标注清楚、走评审。
- **关卡**:模块怎么切、哪些进库、哪些升 stable。
- 完成 → `mark --stage knowledge`。

### ④ coding — 编码 profile [AI起草+人确认，调 project-coding-profiles]

- 在 `project-coding-profiles` 建 `profiles/<project>/{profile.json, coding-mode.md}`,
  填 rootMarkers(项目独有文件,验证真实存在)、encoding、codingMode。
- **关键定性**:GBK 老项目 → 重点是**编码守护**(防乱码);UTF-8 框架项目(如芋道/微服务)
  → 重点是**框架分层约定**,编码守护是 no-op。别套错模板。
- **关卡**:profile 定性对不对、rootMarkers 能否命中项目根。
- 完成 → `mark --stage coding`。

### ⑤ aggregate — 前后端聚合 [自动，调 yoooni-taskspace]

- 仅前后端分离/多仓系统需要。`pipeline.mjs aggregate` 内部调 yoooni-taskspace 建 junction 工作区。
- 顶层再写一份**系统级 CLAUDE.md**(全景 + 前后端对接关系),与 `.taskspace.json` 同级。
- 聚合工作区是本地视图,**通常不进 git**。
- 完成 → `mark --stage aggregate`(单仓项目可 `--status skipped`)。

### ⑥ topology — 跨项目拓扑 [人判定，归 cross-project-topology]

- 若发现本系统调用其它系统(如 .env 里指向别的服务、Feign 调外部),
  这类**跨 ≥2 项目**的调用链归 `cross-project-topology`,**不进本系统两仓也不进 domain-knowledge**。
- **关卡**:有没有跨项目集成、要不要登记。没有就 `--status skipped`。
- 完成 → `mark --stage topology`。

## 收尾

- `pipeline.mjs status` 出总进度。
- 各产物分别提交到**各自的仓**(知识图谱→domain-knowledge / profile→coding-profiles /
  CLAUDE.md→各项目仓),走 team-standards 的 git-commit-standards;聚合工作区不提交。
- 汇总:本次 onboard 了哪个系统、产出多少知识点/哪些 profile/几份 CLAUDE.md。

## 工作台一键

工作台(kai-toolbox 项目工作台)可对一个项目暴露「初始化」按钮 → 触发本 skill + 传项目路径,
即从 `plan` 开始走流水线。底层仍是「编排 + 关卡」,不是无人值守。

## 与下层能力的关系（不重造）

| 阶段 | 调用 |
|---|---|
| ③ knowledge | domain-knowledge-bootstrap skill + bootstrap.mjs(gaps/scan/new/check) |
| ④ coding | project-coding-profiles(profiles/ 登记) |
| ⑤ aggregate | yoooni-taskspace skill(taskspace.mjs) |
| ⑥ topology | cross-project-topology 仓库 |

本 skill 只做编排与关卡,逻辑都在下层。
