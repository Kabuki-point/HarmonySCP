# x86_64 模拟器 SSH 验证（2026-11-03）

本页保留当次临时脚本验证的事实与命令。后续脚本已整理到 `tests/ssh-gui/`，当前复现方式统一使用 uv 和根目录 `requirements.txt`，见 [运行说明](ssh-gui-testing.md)。

## 环境与范围

Codex 在当前 x86_64 / API 26 模拟器上，通过 `hdc shell uitest` 操作实际 HarmonySCP 页面，加载前次构建的双 ABI HAP 中的 Native 库。服务端为 WSL 环回地址上的临时 Paramiko 5.1.0 SSH 服务，使用内存中生成的 RSA 2048 位主机密钥和随机合成密码，不使用系统账户，不修改系统 sshd 配置。

被测 HAP SHA256：`ca361141eae589bc18532c42e3f3f350ff99d61dc447b5f49118cd8fe7e61322`。

链路：应用 `127.0.0.1:2222` → HDC 反向转发 → Windows 本地端口 `23222` → WSL 临时 SSH 服务。不是预览 mock，也不是仅在宿主机运行 Native 测试。

## 已验证结果

| 场景 | 实际证据 | 结果 |
| --- | --- | --- |
| 握手、指纹确认、正确密码登录、主动断开 | 页面指纹与服务端真实主机密钥 SHA256 完全一致；确认前 0 次认证，确认后服务端密码认证成功；页面显示“已安全连接”，断开后回到“准备连接”且服务端连接关闭 | 通过 |
| 拒绝指纹 | 服务端握手完成，点击“拒绝并断开”后关闭连接，0 次密码认证请求 | 通过 |
| 错误密码 | 核对指纹后提交错误合成密码；服务端记录认证失败，页面显示“连接失败” | 通过 |
| 登录后服务端关闭连接 | 服务端先记录认证成功，再主动关闭；应用最终显示“服务器连接已断开” | 通过，但有延迟 |
| 握手阶段取消 | 服务端接受 TCP 但不响应 SSH；页面进入“安全握手”，点击取消后回到“准备连接”，服务端连接关闭，0 次认证请求 | 通过 |
| 不可用端口 | 填写未转发、未监听的模拟器端口；页面显示“连接失败”，测试 SSH 服务未收到新连接 | 通过 |
| 切后台断开并回前台 | 成功登录后按 Home，服务端连接关闭；重新打开应用，页面回到“准备连接” | 通过 |

7 个独立场景均完成，最终驱动退出 0 并输出 `All 7 emulator UI SSH scenarios passed`。错误认证、拒绝指纹及远端关闭之后均实际发起后续连接，验证了失败后能够重试。

## 验证操作与证据

临时 Python 环境和测试驱动位于忽略的 `build/`，未加入版本控制；凭据不输出到命令行日志。主要命令：

```sh
python3 -m venv build/ssh-test-venv
build/ssh-test-venv/bin/pip install paramiko==5.1.0
build/ssh-test-venv/bin/python -u build/emulator-ssh-server.py
hdc -t <emulator> rport tcp:2222 tcp:23222
build/ssh-test-venv/bin/python build/emulator-ui-test.py fill
build/ssh-test-venv/bin/python build/emulator-ui-test.py button 连接服务器
build/ssh-test-venv/bin/python build/emulator-ui-test.py trust
build/ssh-test-venv/bin/python -u build/emulator-ssh-scenarios.py
```

这些脚本是本机临时测试驱动，不是仓库内跨环境可直接复现的测试套件。其他环境复测时，可基于 `tests/native/integration.py` 的 Paramiko 服务端逻辑创建独立环回服务；在模拟器页面填入合成账号，通过可信渠道计算并核对指纹后，再进行密码认证。设备端只采集布局、状态及匿名服务端事件，不将设备日志或凭据纳入仓库。

测试驱动最初误将 UI 工具的 `No Error` 当作错误；另发现 `uitest inputText` 会追加输入。修正临时驱动后，使用全选、删除、输入和字段一致性检查，应用代码未因此修改。

测试结束后，`hdc fport rm tcp:2222 tcp:23222` 返回删除成功，`hdc fport ls` 返回空；停止本次服务进程，删除随机合成凭据文件和本次采集的本地/设备布局文件，并重新启动应用清除测试表单。系统 SSH 服务、账户、安全配置未修改。匿名场景结果保留在忽略的 `build/emulator-ssh-test/results.json`，不将设备日志或构建产物提交。

## 限制

服务端断开场景第一次未在驱动设置的 8 秒观察窗口内出现错误；复测放宽观察窗口后通过，从开始执行指纹确认操作到观察到失败共约 17.29 秒（含 UI 定位、点击和读取，不是精确的 TCP 断线传播耗时）。不能宣称断线即时可见；本次不修改断线检测实现。

未验证 ARM64 真机、系统 OpenSSH 服务、IPv6、密钥认证、文件传输或终端能力。未验证 TCP/认证 15 秒超时、指纹等待 120 秒超时、真实网络断开及内存擦除。未执行设备 Hypium 套件；这些 UI 场景不能替代完整验收清单。
