# 模拟器验证 SFTP 单文件往返

- 日期：2026-11-04（Asia/Shanghai）
- 执行者：Codex 与用户
- 关联：桌面仓库分支 `feature/sftp-single-file`

## 需求与目的

从 DevEco Studio 构建并运行当前分支，使用 Mac 的远程登录服务验证设备端 SFTP 单文件上传和下载。

## 操作与验证

- 在 DevEco Studio 选择已有的 Mate 90 Pro 模拟器，运行 `entry`。IDE 日志显示 HAP 安装成功并启动应用，HDC 确认应用进程运行。模拟器为 ARM64 / HarmonyOS 7.0 / API 26。
- 模拟器通过 Mac 局域网地址访问 OpenSSH。此前应用连接临时环回转发端口时出现一次 TCP 拒绝。切换地址后，用户在模拟器输入密码并操作指纹确认，应用日志显示 `verify`、`authenticating`、`connected`。
- 用户在应用内操作下载、Picker 导出和上传。通过设备端 `sha256sum`、Mac 上的 `shasum -a 256` 与 `cmp` 校验，Mac 原文件、模拟器导出文件和带 `renew` 后缀的回传文件内容一致。测试文件为 47 字节，Mac 测试目录未见上传临时文件残留。
- 更新 [SFTP 验证说明](../validation/sftp-validation.md)、项目进度和文档索引。检查链接及 `git diff --check`。

## 限制与后续

本次覆盖真实 OpenSSH 的单文件往返与系统 Picker。真机及设备端同名、取消、断网和其他异常场景仍待验证。
