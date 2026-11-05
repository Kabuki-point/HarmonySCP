# SFTP 远程文件管理

- 日期：2026-11-04（Asia/Shanghai）
- 执行者：Codex
- 分支：feature/sftp-file-manager，基于已备份的单文件传输提交 12a1e6d

## 需求与目的

增加目录列表和路径导航，从列表发起单文件上传和下载，并支持新建文件夹、重命名及删除单个文件或空目录。

## 具体操作

- SFTP 工作线程串行处理传输和目录请求。目录列表以服务器解析后的绝对路径为准，限制为 5000 项。符号链接可见，管理操作仅作用于普通文件和文件夹。重命名使用禁止覆盖的标志，删除文件夹由服务器检查是否为空。
- 更新 Native 桥接、类型和预览 mock。远程文件面板复用本地 Picker 和传输进度，操作成功后刷新目录，删除前显示目标并要求确认。
- 扩展本机 Paramiko 集成测试与 [设备验收清单](../validation/sftp-validation.md)。

## 验证

- DevEco assembleHap 构建通过，核对 arm64-v8a 和 x86_64 的 libentry.so 及 libc++_shared.so ELF 架构。
- macOS 使用 clang++、官方 libssh2 1.11.1 本机归档和 Paramiko 执行 tests/native/integration.py。6 个 SSH 场景与 SFTP 单文件、目录管理、异常和取消测试全部通过。
- Git 差异空白检查、文档链接与根目录 README 零字节检查通过。

## 限制与后续

本次 HDC 无在线设备。新的列表与 Picker 联动、目录操作提示和刷新待模拟器或真机端到端验证。系统 Picker 若触发切后台断开，用户可在重连后选择目录再上传已选文件。
