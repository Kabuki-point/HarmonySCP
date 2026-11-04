# 指定桌面工作区

- 日期：2026-11-04（Asia/Shanghai）
- 执行者：Codex
- 关联：本地分支 `ai/desktop-workspace`

## 需求与目的

按用户要求，将后续 HarmonySCP 代码修改集中在桌面工作区，避免改到同名的 ChatGPT 项目副本。

## 具体操作

- 在仓库根目录 `AGENTS.md` 的基本操作中写明工作目录和修改前的核对要求。
- 在 `docs/README.md` 登记本记录。

## 验证

使用 `git rev-parse --show-toplevel`、`git status --short --branch` 与 `git remote -v` 核对目标仓库，执行 `git diff --check` 并检查文档链接及根目录 README 的空白状态。本批为文档变更。

## 限制与风险

旧副本中的既有改动未迁移。

## 后续事项

后续代码修改开始前先确认桌面仓库根目录。
