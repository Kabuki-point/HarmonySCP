# MVP 验证记录（2026-11-02）

本页保留当时验证事实。2026-11-03 新增的实际 x86_64 / API 26 模拟器 SSH UI 验证见 [后续验证记录](emulator-ssh-validation.md)，不据此将 ARM64 真机或完整设备清单标为通过。

## 实际完成

- DevEco 自带 OHPM 同步、Hvigor assembleHap 成功。未配置签名。
- ARM64 Native C++17 与 ArkTS 编译成功。工具链存在 gcc-toolchain 参数未使用警告。
- macOS 上使用同一份 ssh_client.cpp、官方 libssh2 1.11.1 源码（链接本机 OpenSSL 3）与 Paramiko 5.1.0 运行真实 SSH 集成测试，6 个场景全部通过：
  - 成功握手与密码登录、主动断开。
  - 错误密码返回错误。
  - 拒绝主机指纹并断开，服务端收到 0 次认证请求。
  - 服务端登录后关闭 TCP，客户端转为错误。
  - 服务器不回应 SSH 握手时取消，1 秒内清理。
  - 本地端口拒绝连接，客户端返回错误。
- 每个场景额外检查非法输入、并发连接拒绝、认证前置条件、错误指纹拒绝、清理后可重连。
- 与 Paramiko 服务器的真实密钥计算出的 OpenSSH 格式 SHA256 指纹逐字比较成功。

## 复现本机集成测试

不需要真实服务器账户。测试服务器只监听 loopback，动态端口和随机 RSA 密钥；合成测试账号不用于其他服务。

1. 使用根目录 `requirements.txt` 和 uv 创建/同步 `.venv`，命令见 [Python 测试环境](ssh-gui-testing.md)。
2. 下载官方 libssh2 1.11.1，使用 CMake 和本机 OpenSSL 构建静态库。
3. 编译测试程序（按本机库位置调整最后几个参数）：

```sh
clang++ -std=c++17 -pthread tests/native/ssh_client_test.cpp \
  entry/src/main/cpp/ssh_client.cpp entry/src/main/cpp/sftp_transfer.cpp \
  entry/src/main/cpp/terminal_session.cpp \
  -Ientry/src/main/cpp -Ientry/libs/include \
  /tmp/harmony-libssh2-host/src/libssh2.a \
  -L/opt/homebrew/opt/openssl@3/lib -lcrypto -lz -o /tmp/harmony-ssh-client-test
.venv/bin/python tests/native/integration.py /tmp/harmony-ssh-client-test
```

## 尚未执行的设备验收

没有连接可用的 HDC 设备，未安装或运行 HAP，未执行 `entry/src/ohosTest`。
本机测试没有加载鸿蒙 ARM64 libcrypto.a，不能替代设备测试。

- [ ] 在 ARM64 / API 24+ 设备安装签名 HAP，检查布局、键盘、小屏滚动及指纹确认卡片。
- [ ] 分别连接 IPv4、IPv6 实际服务器，核对其所协商密钥指纹并登录。
- [ ] 覆盖密码错误、服务器关闭密码认证、错误端口、无网络和服务器不可达。
- [ ] 在 TCP/握手/指纹等待/认证阶段取消，并连续重复连接与断开。
- [ ] 验证 TCP/握手/认证 15 秒超时、指纹确认 120 秒超时。
- [ ] 登录后主动断网、关闭服务器；检查状态、重连及资源占用。
- [ ] 切后台/退出页面断开，回前台重新登录且密码字段已清空。
- [ ] 执行设备端 NativeSshInputContract Hypium 测试。

## 已知限制

每次手动验证指纹，不保存 known_hosts。IP 字面地址不支持域名及 IPv6 zone ID。
保活发送失败和 TCP 关闭可被发现；无业务通道时，对静默丢包的断线发现没有严格时限。
密码的 ArkTS 字符串由运行时管理，无法保证物理内存立即覆写；应用不将密码写入存储或日志。
首版只有连接管理，不提供终端或文件传输。


## 预览器登录失败排查与修复（2026-11-02）

实际观察：DevEco 顶部目标为“预览器”，HiLog 显示“无设备”，HDC 设备列表为空；用户确认是在预览器中尝试登录。工程的 Native mock 不发起 SSH 连接，因此无法在该模式登录，并无此次设备端密码认证失败日志。

修复：

- Native 状态接口新增 nativeAvailable，设备返回 true，预览 mock 返回 false 和独立 preview 状态。
- 页面常驻显示预览限制，禁用连接表单与登录按钮，避免将预览限制误报为 IP 错误。
- 密码只在连接结束或成功的状态切换时清理，修复 error 状态轮询不断清空重试输入的问题。
- 表单校验提示不再被每 200ms 的相同 Native 状态覆盖。
- Native 日志 tag 为 HarmonySCP，仅记录状态、阶段、errno / SSH 返回码，不记录地址、用户名、密码或服务器返回的原始文本。

验证：最终 assembleHap 成功；同一 Native 核心的 6 个本机 SSH 集成场景再次全部通过；git diff --check 通过。未连接真机/模拟器，未完成设备侧登录和新增日志运行验证；预览提示改动已编译，但未完成其界面运行验收。

下一次验证：在 DevEco 顶部选择在线 ARM64 手机或已启动的 ARM64 模拟器（API 24+），运行应用；HiLog 选择该设备和应用，在 tag 栏输入 HarmonySCP。仍然失败时，根据 tcp-connect / handshake / password-auth 阶段和错误码定位。


## 用户验证反馈（2026-11-02）

用户在后续会话中反馈“我验证了没问题”。这是用户报告的验证结果；尚未记录设备型号、镜像版本、服务器类型和具体通过场景。此前 agent 未执行的设备验收条目仍保留，后续按实际证据补充，不将用户反馈解释为所有清单均已通过。
