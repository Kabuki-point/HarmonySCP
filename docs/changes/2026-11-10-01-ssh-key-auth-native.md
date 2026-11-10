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

## 限制与风险

- **未运行本机集成测试**：`tests/native` 需要宿主机 libssh2（Linux/macOS 上编译 C++ 测试程序），当前 Windows 环境无宿主机 libssh2，且 WSL 未安装，无法在本机执行。因此 `pubkey-*` 四个场景**尚未实际运行**，只完成语法检查。
- **未做设备验证**：`hdc list targets` 为空，无真机或模拟器，未验证真实页面与真实 OpenSSH 服务器。
- **`frommemory` 传 `nullptr` 公钥未实测**：官方文档说明公钥可从私钥提取，但本版本未在运行时验证；若失败需退回「同时提供 `.pub`」方案。
- **格式兼容性未实测**：libssh2 归档中存在 `_libssh2_bcrypt_pbkdf` 与 `OPENSSH PRIVATE KEY` 标识，推断支持 OpenSSH 新格式，但本机 `ssh-keygen` 生成的 OpenSSH 格式文件未实际送入 libssh2 验证。
- **错误码映射未实测**：`LIBSSH2_ERROR_FILE` 是否确实对应私钥解析失败，基于文档推断，需运行时确认。
- 口令输入为空时传 `nullptr`，未加密私钥场景依赖此路径。

## 后续事项

1. 在具备宿主机 libssh2 的环境（Linux/macOS 或安装 WSL）运行 `tests/native/integration.py`，实测 4 个公钥场景与既有回归。
2. UI 层：新增密钥选择面板与认证方式切换（第二批）。
3. 设备端用真实 OpenSSH 验证 Ed25519 与 RSA 私钥登录，并确认 SFTP 功能在公钥会话下正常。
4. 依据实测结果修正 `KeyAuthMessage` 的错误码映射。
