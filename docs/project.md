# HarmonySCP 项目进度

更新时间：2026-11-02（Asia/Shanghai）。此文件记录项目背景与实际状态；agent 工作约束见根目录 [AGENTS.md](../AGENTS.md)。

## 当前版本

已在原 DevEco Native C++ 模板上实现第一阶段 SSH 客户端 MVP。

- ArkUI 中文连接页：IP、端口、用户名、密码、状态与错误提示。
- Native 后台线程完成 TCP、SSH 握手、SHA256 主机指纹获取、密码认证。
- 每次连接均需人工核对并确认指纹，确认前不发送认证凭据；不自动信任指纹。
- 支持取消、主动断开、失败重连、服务端 TCP 关闭检测；切后台断开。
- 密码不持久化、不写日志；认证后清除页面密码并覆盖 Native 密码缓冲区。
- TCP/握手/认证分别最多 15 秒；指纹确认最多 120 秒。
- 首版仅 ARM64、IPv4/IPv6 字面地址；不支持域名、终端、命令执行、SFTP、SCP、文件传输与连接收藏。

## 环境与构建

DevEco Studio 26.0.0.865，目标 API 26，最低 API 24，Stage / Phone，C++17，BiSheng，arm64-v8a。

在 DevEco 打开本目录，同步 OHPM 依赖后构建 entry。CLI 示例（macOS 默认安装位置）：

```sh
export DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk
export JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home
export PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH
ohpm install
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

输出 `entry/build/default/outputs/default/entry-default-unsigned.hap`。个人签名在 DevEco 本机配置，不入库。

## 使用

预览器仅展示界面，不能连接 SSH；请在顶部运行目标选择 ARM64 真机或模拟器。设备排错可在 HiLog 按 tag `HarmonySCP` 筛选状态与错误码。

1. 用满足 API 24 的 ARM64 手机或模拟器运行；服务器需启用 SSH 密码认证。
2. 输入设备可达的服务器 IP、端口、用户名和密码。模拟器的 127.0.0.1 指向模拟器自身。
3. 点击连接，等待出现指纹卡片（小屏幕向下滚动）。
4. 从可信渠道取得服务器指纹，例如管理员在服务器执行 `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256`。服务器可能协商其他类型主机密钥，应核对实际对应的密钥。
5. 指纹一致才确认登录；不一致则拒绝。成功后显示“已安全连接”，可主动断开。

## 验证与后续

- `assembleHap` 已实际通过，HAP 包含 ARM64 libentry.so 与 libc++_shared.so。
- 原生连接核心在 macOS + 同版本 libssh2 1.11.1（本机构建、OpenSSL 3 后端）通过 6 个真实本机 SSH 集成场景。
- agent 未执行设备端 Hypium 测试；本机测试不等同于验证打包的 ARM64 二进制。
- 2026-11-02 用户反馈“我验证了没问题”。设备型号、镜像版本和逐项测试结果未提供，未据此将完整设备验收清单标为通过。
- 依赖来源、校验值、版本限制见 [第三方依赖记录](../third_party/NOTICE.md)。参考工程的 OpenSSL 预编译依赖构建来源与补丁不完整，发布前需替换为可复现构建、完成安全审核和设备验证。
- 设备验收清单与测试复现见 [MVP 验证记录](validation/mvp-validation.md)。

团队仓库：https://github.com/Kabuki-point/HarmonySCP 。提交与同步状态以 Git 为准。
