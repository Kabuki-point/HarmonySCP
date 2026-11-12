# SSH 公钥认证：设备端验证尝试与阻塞

- 日期：2026-11-12（Asia/Shanghai）
- 执行者：DSH agent（workbuddy/deepseek-v4.1-flash）
- 关联：分支 `feature/ssh-key-auth`，基于 `daef713`；本次未提交代码，仅新增测试文件与文档

## 需求与目的

在 x86_64 / API 26 模拟器上验证 SSH 公钥认证。本批只有 Native 层与接口，UI 没有密钥入口，因此计划通过 `ohosTest` 直接调用 `ssh.authenticateWithKey` 验证真实链路。

## 实际完成

以下为 agent 实测，均在 `127.0.0.1:5555`（x86_64 / API 26）上执行。

| 项目 | 结果 |
| --- | --- |
| `hdc list targets` 识别设备 | 通过 |
| 主 HAP 免签名 `hdc install` | 通过，应用启动后页面正常渲染 |
| `hvigor ... -p module=entry@ohosTest assembleHap` | 通过，无需补 `module.json5` |
| 测试 HAP `hdc install` | 通过，`entry_test` 模块注册成功 |
| `aa test -b com.example.har_scp -m entry_test -s unittest OpenHarmonyTestRunner` | 通过，8 个用例全部执行 |
| 设备端用例结果 | `Tests run: 8, Failure: 0, Error: 0, Pass: 8` |

新增 `entry/src/ohosTest/ets/test/KeyAuth.test.ets`，6 个契约用例：握手前调用、指纹不匹配、空用户名、空密钥、超大密钥（>64 KiB）、超长口令，均断言返回 `false`。

## 关键发现：设备端测试实际跑的是 mock

8 个用例虽然在真实设备上通过，但**不能作为公钥认证已验证的证据**。诊断过程：

1. 新增临时诊断用例，把 `ssh.connect('127.0.0.1', 2222)` 后的状态逐帧打印；
2. 断言消息显示 `state=preview`、`msg=当前为界面预览，无法连接 SSH`；
3. 该文案正是 `entry/src/mock/Libentry.mock.ets` 中写死的预览状态；
4. 检查测试 HAP 内容：含 `resources/rawfile/mock/mock-config.json`，**不含 `libs/*/libentry.so`**；
5. `bm dump` 对比：主模块 `nativeLibraryPath = libs/x86_64`，测试模块 `entry_test` 为**空**。

结论：`ohosTest` 是独立打包的 feature HAP，不继承主模块的 native 库，构建时把 `src/mock/mock-config.json5` 打入测试包，于是 `import ssh from 'libentry.so'` 绑定到预览 mock。

尝试清空 `mock-config.json5` 后重建，测试包仍不含 native 库，说明与 mock 配置无关，而是测试模块打包机制的固有行为（未找到可覆盖的 hvigor 配置项）。

因此端到端密钥登录（真实 Paramiko 服务 + `hdc rport`）**未验证**。

## 保留的代码与用途

以下文件已保留，并加注释标明当前限制，等待方案 A（补 UI 入口后经真实页面验证）复用：

- `entry/src/ohosTest/ets/test/KeyAuth.test.ets`：NAPI 契约用例，文件头注明“实际绑定 mock，不是真实链路”
- `entry/src/ohosTest/ets/test/List.test.ets`：入口注释同步说明该限制
- `tests/ssh-gui/key_server.py`：仅允许 `publickey` 的环回测试服务，文档字符串注明“已准备但尚不可端到端使用”，并实现 `check_auth_publickey` 内按 `auth_mode` 显式拒绝（Paramiko 的 `get_allowed_auths` 不强制限制，此坑已在 [11-10 记录](2026-11-10-01-ssh-key-auth-native.md) 记录）

## 环境清理

- 已删除设备侧反向端口转发 `tcp:2222 → tcp:23222`（`hdc fport ls` 返回空）
- 已终止 `key_server.py` 相关进程（PID 36616 监听进程、35788 启动器），23222 端口释放
- 已删除进程强杀后残留的合成密钥文件与日志（`build/ssh-gui/*`，该目录已被 `.gitignore` 忽略）
- 未卸载设备上的应用与测试包

## 限制与风险

- **公钥认证在设备上仍未经真实链路验证**。已验证的只有：Native 库能编译进主 HAP、主 HAP 能安装启动、NAPI 契约在 mock 下行为正确。
- 主 HAP 经 `bm dump` 确认含 `nativeLibraryPath = libs/x86_64`，说明真实库已随主包安装，只是测试进程无法加载。
- ARM64 真机路径依旧未覆盖。

## 后续事项

1. **方案 A**：完成第二批 UI（密钥选择面板、认证方式切换、Picker 读入私钥），经真实页面操作验证公钥登录与 SFTP。
2. 验证时可直接复用 `tests/ssh-gui/key_server.py` 与现有 `uitest` 驱动。
3. 若坚持设备端测试路线，需解决“测试模块携带 native 库”问题（未找到标准做法，风险较高，不建议）。
