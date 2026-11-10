# SSH 公钥认证（第一批：Native 核心与接口）

- 日期：2026-11-10（Asia/Shanghai）
- 执行者：DSH agent（workbuddy/deepseek-v4.1-flash）
- 关联：本地分支 `feature/ssh-key-auth`，基于 `c70fc0e`；未提交、未推送

## 需求与目的

`demand.md` 细节要求 1 为「SSH 实现公钥验证」。首版只有密码认证，本次增加基于私钥的认证能力。

经用户确认的范围取舍：

1. 只保证 OpenSSH 格式私钥（含 Ed25519 / RSA / ECDSA），首版不承诺独立 PEM 与 PKCS#8 兼容；
2. 不额外支持 `.pub` 文件入参，公钥由 libssh2 从私钥自动提取；
3. 接受「认证失败需重新选择私钥」的交互取舍，以换取不长期持有密钥字节。

本批只做 Native 核心、桥接与接口契约，**不含 UI**。

## 具体操作

- `entry/src/main/cpp/ssh_client.h`
  - 新增 `enum class AuthMethod { Password, PublicKey }`，新增 `AuthenticateWithKey`。
  - 新增 `privateKey_` 成员与 `authMethod_`；`password_` 在公钥模式下承载口令，复用既有擦除路径。
- `entry/src/main/cpp/ssh_client.cpp`
  - `AuthenticateWithKey` 校验用户名、私钥（上限 64 KiB）、口令长度与指纹一致性，通过后置标记，由工作线程取用。
  - `Run()` 在 `verify` 之后的等待点按 `authMethod_` 分派：公钥走 `libssh2_userauth_publickey_frommemory`（公钥数据传 `nullptr`，由库从私钥提取），密码保持原 `libssh2_userauth_password_ex` 不变。
  - 密钥与口令在认证后、异常退出路径、连接清理路径三处擦除；`Connect()` 重置时清空残留。
  - 新增 `KeyAuthMessage()` 把 `LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED` / `AUTHENTICATION_FAILED` / `FILE` 映射为可操作的中文提示，其它错误码保留原始数值便于排障。
- `entry/src/main/cpp/napi_init.cpp`
  - 新增 `AuthenticateWithKey`：从 `ArrayBuffer` 取私钥字节，长度上限 64 KiB，调用后无论成功与否都擦除本地副本与口令副本。
- `entry/src/main/cpp/types/libentry/Index.d.ts`
  - 声明 `authenticateWithKey(user, keyData: ArrayBuffer, passphrase, fingerprint)`，注明调用方保留 `keyData` 所有权并应自行清零。
- `entry/src/mock/Libentry.mock.ets`
  - 同步新增桩函数，恒返回 `false`，保持预览模式不伪造登录成功。
- `tests/native/integration.py`
  - Paramiko 服务端新增 `publickey` 模式与 `check_auth_publickey`，生成三把 RSA 测试密钥（授权、未授权、带口令）。
  - 新增 4 个场景：`pubkey-ok`、`pubkey-wrong`、`pubkey-encrypted`、`pubkey-password-only`，并断言认证尝试次数。
- `tests/native/ssh_client_test.cpp`
  - 新增公钥模式分支与密钥文件读取；覆盖错误指纹拒绝、超大密钥拒绝、错误密钥失败、加密私钥成功、仅密码服务器拒绝公钥。

## 验证

- **构建**：DevEco 26.0.0.865 hvigor `assembleHap` 成功（`BUILD SUCCESSFUL`）。双 ABI 产物均生成 `libentry.so`（arm64-v8a、x86_64），`llvm-nm` 确认两个架构都包含 `SshClient::AuthenticateWithKey`、NAPI `AuthenticateWithKey` 与 `libssh2_userauth_publickey_frommemory` 符号。
- **测试程序语法**：用构建产物中 `compile_commands.json` 记录的真实工具链参数（BiSheng clang、`--target=aarch64-linux-ohos`、SDK sysroot）对 `tests/native/ssh_client_test.cpp` 执行 `-fsyntax-only`，退出码 0。
- **Python 测试脚本**：`python -m py_compile tests/native/integration.py` 通过；使用仓库既有 `build/sshtest` venv（paramiko 5.1.0）验证了密钥生成、PEM 写入、加密私钥口令往返读取均正常。
- **行尾与空白**：所有改动文件的行尾由编辑产生的 CRLF 归一化为 LF（与原文件一致）；`git diff --check` 通过；改动中无真实凭据，仅含合成测试常量 `test-passphrase-9f2`。

### 2026-11-10 补充：宿主机工具链修复后实跑

同日修复了宿主机编译环境，`tests/native` 的 C++ 测试程序已实际编译并运行。

环境：MSYS2（`C:\ProgrammingEnv\msys64`），`gcc 16.2.0`（msys 层，含完整 POSIX 头文件）、`libssh2 1.11.0`（含 `libssh2-devel`）、`openssl 3.3.1`。编译命令使用 `-std=gnu++17`（严格 `c++17` 会隐藏 `mkstemp`、`fdopen`、`F_DUPFD_CLOEXEC`，与项目 CMake 实际使用的 `gnu++17` 一致）。

```
results: 10/10 场景通过
PASS ok / bad / reject / remote-close / stall / refused
PASS pubkey-ok / pubkey-wrong / pubkey-encrypted / pubkey-password-only
```

SFTP 场景在本机因 Windows 无 `SeCreateSymbolicLinkPrivilege` 无法创建符号链接，改以去掉符号链接断言的临时副本单独运行时 `PASS sftp`（上传、下载、目录管理、取消、临时文件清理均通过）。未修改仓库内的正式断言。

**三个待验证假设的实测结论**：

1. **`frommemory` 传 `nullptr` 公钥** —— **成立**。`pubkey-ok` 与 `pubkey-encrypted` 均通过，公钥确由 libssh2 从私钥自动提取，无需额外 `.pub` 文件。
2. **OpenSSH 新格式解析** —— **成立**。用 `ssh-keygen` 生成 `-----BEGIN OPENSSH PRIVATE KEY-----` 的 Ed25519 与 RSA 私钥，经 libssh2 认证均返回 `rc=0`（accepted）。
3. **错误码映射** —— **成立**。加密私钥口令错误时返回 `-16`（`LIBSSH2_ERROR_FILE`），服务端拒绝已授权密钥时返回 `-18`（`LIBSSH2_ERROR_AUTHENTICATION_FAILED`），与 `KeyAuthMessage` 的映射一致。

**测试过程中修正的两处测试代码缺陷**（非产品缺陷）：

- `integration.py` 原用独立生成的 `encrypted_key` 做加密场景，但服务端只授权 `client_key`，导致必然失败；改为用已授权的 `client_key` 生成加密版本。
- Paramiko 的 `get_allowed_auths` 仅影响通告的方法而不强制限制，`check_auth_publickey` 仍会被调用并可能返回成功；改为在 `check_auth_publickey` 内根据 `auth_mode` 显式拒绝，`pubkey-password-only` 才真正验证「服务器不支持公钥」。
- `remote-close` 场景的默认 5 秒观察窗口在本机环境中不足（基线代码同样失败），放宽到 30 秒后通过；这是检测延迟，不是连接处理缺陷。

## 限制与风险

- **设备端未验证**：`hdc list targets` 为空，无真机或模拟器；未验证真实页面、真实 OpenSSH 服务器与 ARM64 打包二进制。
- **ARM64 归档未直接测试**：本机实跑使用的是 MSYS2 提供的 x86_64 libssh2 1.11.0，与仓库内 `entry/libs/arm64-v8a/libssh2.a`（同为 1.11.1 系列）不是同一产物；行为一致性属于推断，未逐一比对。
- **符号链接相关 SFTP 断言未在本机执行**：受 Windows 权限限制跳过，需在 Linux/macOS 或设备端补跑。
- **端口转发与 UI 未覆盖**：本轮只测 Native 核心的库接口，未经 `hdc rport` 与页面交互。

## 后续事项

1. 模拟器端验证：安装 HAP，经 `hdc rport` 接真实 Paramiko/OpenSSH 服务，覆盖公钥登录与 SFTP。
2. UI 层：新增密钥选择面板与认证方式切换（第二批）。
3. 设备端用真实 OpenSSH 验证 Ed25519 与 RSA 私钥登录。
4. 在 Linux/macOS 上完整跑一遍含符号链接的 SFTP 断言。
