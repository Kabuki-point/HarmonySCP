# 实现 SFTP 单文件传输

- 日期：2026-11-04（Asia/Shanghai）
- 执行者：Codex
- 分支：`ai/sftp-single-file`，无提交或 PR

## 需求与目的

参考 CrossShellNext 的 Picker、文件描述符与 Native 分块读写方式，实现单文件上传与下载。复用现有 SSH 主机指纹确认及认证流程。

## 具体操作

- `entry/src/main/ets/components/SftpPanel.ets`、`pages/Index.ets`：新增传输界面、上传选择、进度、取消、沙箱下载缓存及 Picker 导出。页面允许在连接前选好上传文件；上传源使用只读模式打开。
- `entry/src/main/cpp/sftp_transfer.*`、`ssh_client.*`：在现有 SSH worker 上按任务打开 SFTP 子系统，每次处理一个文件，支持短写、`EAGAIN`、无响应超时、取消和资源清理。上传使用独占创建的远端临时文件与禁止覆盖的改名操作。
- `napi_init.cpp`、`Index.d.ts`、`Libentry.mock.ets`：同步传输入口及状态。Native 复制 fd 并独立关闭，使用连接编号拒绝在文件准备期间已发生重连的请求。预览不执行传输。
- `CMakeLists.txt`、`entry/libs/include/libssh2_sftp.h`、`third_party/NOTICE.md`：纳入 SFTP 源文件和官方 1.11.1 头文件，沿用双 ABI 静态库。
- `tests/native/`：扩展现有 Paramiko 环回集成测试，覆盖数据完整性、同名保护、取消与重试。新增 [SFTP 验证说明](../validation/sftp-validation.md) 并更新项目文档。

## 验证

- libssh2 1.11.1 官方源码包 SHA256 与已有记录一致，头文件与该源码包逐字节一致。
- DevEco CLI `assembleHap --no-daemon` 构建成功。HAP 包含 `arm64-v8a`、`x86_64` 的 `libentry.so` 及 C++ 运行库。产物为未签名 HAP。
- macOS 用官方 libssh2 1.11.1 源码和本机 OpenSSL 3 构建测试程序，执行 `tests/native/integration.py`。6 个既有 SSH 场景和 SFTP 场景全部通过。
- `git diff --check`、文档本地链接及根目录 README 零字节检查通过。

## 限制与风险

HDC 设备列表为空。尝试启动现有 ARM64 模拟器实例时日志提示无法读取实例 UUID，DevEco 设备管理器也显示无可用模拟器。未安装 HAP，未运行模拟器或真机界面、系统 Picker 和 OpenSSH 设备端验收。SFTP 原生测试使用本机编译的 libssh2 和 Paramiko，不能验证鸿蒙端运行表现。连接中断时，远端临时文件清理和改名结果取决于服务器是否已处理请求。

## 后续事项

按 [设备验收清单](../validation/sftp-validation.md) 完成模拟器与真机的端到端验证。

## 迁移到桌面工作区

- 将实现迁入用户当前使用的 `ai/desktop-workspace` 工作树，保留桌面仓库已有的 `AGENTS.md` 改动，并补齐原实现依赖的 `4b45956` 双 ABI 构建与测试基线。
- 在桌面仓库重新执行 DevEco CLI `assembleHap --no-daemon`，构建成功。检查未签名 HAP 中两种 ABI 的 ELF 架构均正确。
- 用桌面仓库源码重新编译本机测试，运行 `tests/native/integration.py`，6 个 SSH 场景和 SFTP 集成场景通过。未执行设备端验收。
- `git diff --check`、文档链接和根目录 README 零字节检查通过。迁移保留为本地工作树改动。
