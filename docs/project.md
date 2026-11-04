# HarmonySCP 项目进度

更新时间：2026-11-04（Asia/Shanghai）。此文件记录项目背景与实际状态；agent 工作约束见根目录 [AGENTS.md](../AGENTS.md)。

## 当前版本

已在原 DevEco Native C++ 模板上实现 SSH 登录与 SFTP 单文件传输。

- ArkUI 中文连接页：IP、端口、用户名、密码、状态与错误提示。
- Native 后台线程完成 TCP、SSH 握手、SHA256 主机指纹获取、密码认证。
- 每次连接均需人工核对并确认指纹，确认前不发送认证凭据；不自动信任指纹。
- 支持取消、主动断开、失败重连、服务端 TCP 关闭检测；切后台断开。
- 密码不持久化、不写日志；认证后清除页面密码并覆盖 Native 密码缓冲区。
- TCP/握手/认证分别最多 15 秒；指纹确认最多 120 秒。
- 支持 ARM64 真机与 x86_64 模拟器构建及 IPv4/IPv6 字面地址。
- SFTP 单文件上传和下载复用已认证的 SSH 会话，支持进度与取消。上传拒绝覆盖同名远端文件，下载完成后可通过系统选择器导出。
- 当前范围不包括域名、终端、命令执行、SCP、远端目录浏览、批量传输、断点续传与连接收藏。

## 环境与构建

DevEco Studio 26.0.0.865，目标 API 26，最低 API 24，Stage / Phone，C++17，BiSheng，arm64-v8a / x86_64。

在 DevEco 打开本目录，同步 OHPM 依赖后构建 entry。CLI 示例（macOS 默认安装位置）：

```sh
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH
ohpm install
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`。个人签名在 DevEco 本机配置，不入库。

Python 测试统一使用 uv 管理的本地 `.venv`，依赖版本记录在根目录 `requirements.txt`：

```sh
uv --cache-dir .uv-cache venv --python 3.12 --no-python-downloads .venv
uv --cache-dir .uv-cache pip sync requirements.txt
```

`tests/native/` 为纯 Native 核心集成测试；`tests/ssh-gui/` 为实际模拟器页面与 SSH 服务测试。HDC 配置、运行和清理步骤见 [SSH GUI 与 uv 说明](validation/ssh-gui-testing.md)。虚拟环境、uv 本地管理文件、缓存和测试运行产物不入库。

## 使用

预览器仅展示界面，不能连接 SSH；请在顶部运行目标选择 ARM64 真机或 x86_64 / ARM64 模拟器。双 ABI 依赖重建与安装检查见 [原生构建说明](validation/native-dependencies.md)。设备排错可在 HiLog 按 tag `HarmonySCP` 筛选状态与错误码。

1. 用满足 API 24 的 ARM64 手机或 ARM64 / x86_64 模拟器运行；服务器需启用 SSH 密码认证。
2. 输入设备可达的服务器 IP、端口、用户名和密码。模拟器的 127.0.0.1 指向模拟器自身。
3. 点击连接，等待出现指纹卡片（小屏幕向下滚动）。
4. 从可信渠道取得服务器指纹，例如管理员在服务器执行 `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256`。服务器可能协商其他类型主机密钥，应核对实际对应的密钥。
5. 指纹一致才确认登录；不一致则拒绝。成功后显示“已安全连接”，可主动断开。

SFTP 服务器需启用 `sftp` 子系统。上传建议在连接前通过“选择上传文件”选好本地文件，登录后填写远端完整路径并点击“上传文件”。下载时填写远端文件路径，点击“下载文件”，完成后再点击“保存下载文件”选择导出位置。操作系统选择器期间如触发切后台，应用会按原有策略断开 SSH。下载缓存可在断开后导出或丢弃。

## 验证与后续

- 2026-11-04 双 ABI HAP 构建与 macOS 本机 SFTP 集成测试通过。同日在 Mate 90 Pro ARM64 模拟器上连接 Mac OpenSSH，完成单文件下载、系统 Picker 保存和上传，两个方向的 SHA-256 均一致。真机与设备端异常场景待验证。详见 [SFTP 验证](validation/sftp-validation.md)。

- `assembleHap` 已实际通过，HAP 包含 ARM64 libentry.so 与 libc++_shared.so。
- 2026-11-03 agent 构建双 ABI HAP 通过，包内 ARM64 / x86_64 的 libentry.so 与 libc++_shared.so 架构均正确；x86_64 模拟器安装、启动及进程存活检查通过，详见 [构建记录](changes/2026-11-03-01-x86_64-emulator.md)。
- 同日 agent 在 x86_64 / API 26 模拟器上通过实际 UI 完成 7 个 SSH 场景：密码登录及主动断开、拒绝指纹、错误密码、服务端关闭、握手取消、不可用端口、切后台断开与回前台。服务端为 WSL 临时 Paramiko 环回服务，使用合成账号；断线提示存在延迟，ARM64 真机、系统 OpenSSH 与完整设备验收仍未完成，详见 [模拟器验证](validation/emulator-ssh-validation.md)。
- 原生连接核心在 macOS + 同版本 libssh2 1.11.1（本机构建、OpenSSL 3 后端）通过 6 个真实本机 SSH 集成场景。
- agent 未执行设备端 Hypium 测试；本机测试不等同于验证打包的 ARM64 二进制。
- 2026-11-02 用户反馈“我验证了没问题”。设备型号、镜像版本和逐项测试结果未提供，未据此将完整设备验收清单标为通过。
- 依赖来源、校验值、版本限制见 [第三方依赖记录](../third_party/NOTICE.md)。参考工程的 OpenSSL 预编译依赖构建来源与补丁不完整，发布前需替换为可复现构建、完成安全审核和设备验证。
- 设备验收清单与测试复现见 [MVP 验证记录](validation/mvp-validation.md)。

团队仓库：https://github.com/Kabuki-point/HarmonySCP 。提交与同步状态以 Git 为准。
