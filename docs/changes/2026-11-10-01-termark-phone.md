# 接入 SSH 终端和 Phone 输入

- 日期：2026-11-10（Asia/Shanghai）
- 执行者：Codex
- 关联：`feature/termark-phone`，基线 `c70fc0e`

## 需求与目的

补齐终端 PTY、Phone 输入适配、页面入口及测试。复用 HarmonySCP 已认证的 SSH 会话，支持从终端返回同一个文件页。

## 具体操作

- `terminal_session.cpp`、`ssh_client.*`：由 SSH worker 打开 shell 和 PTY，处理尺寸变化、输入、输出和资源清理，与 SFTP 互斥。
- `napi_init.cpp`、`Index.d.ts`、预览 mock：增加终端指令和状态接口。输出以 ArrayBuffer 交给页面增量解码，预览保持关闭状态。
- `Index.ets`、`TerminalPage.ets`：在原页面之上打开全屏终端并保留文件面板状态。返回时关闭 PTY，应用生命周期继续负责后台断开。
- TermArk 终端视口使用可见的系统输入框、功能键栏和系统 PasteButton。外接键盘只在输入框接收按键，避免重复分发。保留选择复制和 bracketed paste。
- `tests/native/`、`entry/src/ohosTest/`：补充环回 PTY 场景与 NAPI 基本契约检查。更新 [设备验收清单](../validation/terminal-phone-validation.md) 和依赖记录。

## 验证

- 执行 `git diff --check`、Python 测试文件语法解析、文档相对链接和根目录 README 零字节检查。
- 按用户要求未构建、运行测试或调试。

## 限制与风险

Phone 输入法、外接键盘、粘贴授权和原生渲染的设备表现待验收。服务器须允许 PTY 和交互式 shell。终端打开期间文件操作暂不可用。若 PTY 清理失败，SSH 会话会结束。

## 后续事项

执行环回测试，按设备验收清单验证 Phone 及模拟器。

## 桌面工作区迁移

原改动写入独立副本。后续将基线 `c70fc0e` 和完整的未提交改动迁移到项目指定的桌面工作区，在当地使用 `feature/termark-phone`。迁移按补丁校验文件和 Git 状态，并去除 Unicode 源码末尾多余空行。仍待构建及运行测试。
