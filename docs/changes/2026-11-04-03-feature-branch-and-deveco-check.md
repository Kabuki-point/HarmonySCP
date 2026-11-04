# 功能分支命名与 DevEco 检查

- 日期：2026-11-04（Asia/Shanghai）
- 执行者：Codex
- 关联：桌面仓库本地分支 `feature/sftp-single-file`

## 需求与目的

按功能模块命名当前分支，并核实 SFTP 源文件和头文件在 DevEco 中的编译与编辑器诊断。

## 具体操作

- 将桌面仓库的 `ai/desktop-workspace` 重命名为 `feature/sftp-single-file`。
- 更新 `AGENTS.md` 中的任务分支命名规则，并在文档索引登记本记录。

## 验证

- DevEco Studio 显示桌面仓库与新分支。问题窗口中，`sftp_transfer.cpp` 的 45 条提示均为拼写检查，头文件可见的提示也是拼写检查。
- 使用 SDK 自带 Ninja 清理两种 ABI 的 SFTP 对象文件，再运行 DevEco 的 `assembleHap --no-daemon`。构建成功，重新生成了 ARM64 与 x86_64 的 SFTP 对象文件。
- 构建日志显示 `--gcc-toolchain` 参数未使用及跳过 HAP 签名的提示。
- `git diff --check`、文档链接及根目录 README 零字节检查通过。

## 限制与后续

本次检查覆盖编辑器诊断与构建。设备端验收按 [SFTP 验证清单](../validation/sftp-validation.md) 继续。
