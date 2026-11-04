# SSH GUI 测试与 uv 环境

`tests/ssh-gui/` 保存从临时验证脚本整理出的真实模拟器 UI 测试，不使用预览 mock，也不修改系统 sshd 或账户。它与 `tests/native/` 共用根目录 `requirements.txt` 中的 Python 依赖。

## 环境准备

使用已安装的 Python 3.12 和 uv，在仓库根目录执行：

```sh
uv --cache-dir .uv-cache venv --python 3.12 --no-python-downloads .venv
uv --cache-dir .uv-cache pip sync requirements.txt
```

`requirements.txt` 固定 Paramiko 5.1.0 及本次环境的传递依赖，不包含 pip、私钥或账户。`.venv/`、`.uv/`、`.uv-cache/`、`uv.lock`、本地 `uv.toml`、`.python-version` 和 Python 字节码已忽略；本项目以 `requirements.txt` 作为依赖版本记录，不使用 `uv sync` 的 pyproject 工作流。

下文 Unix/WSL 示例使用 `.venv/bin/python`。Windows 对应 `.venv\Scripts\python.exe`；也可激活 `.venv` 后使用 `python`。不要将 Windows SDK 路径写入脚本或提交本机配置。

## 脚本与配置

| 文件 | 职责 |
| --- | --- |
| `tests/ssh-gui/ssh_server.py` | 创建环回 SSH 服务、内存 RSA 密钥及随机合成密码，模拟正常服务、握手停滞、认证后关闭；Ctrl+C / SIGTERM 时删除凭据 |
| `tests/ssh-gui/ui_driver.py` | 通过 uitest 填表、滚动、点击、读取状态；仅在应用指纹与可信测试密钥一致时确认认证 |
| `tests/ssh-gui/run_scenarios.py` | 每次独立执行 7 个场景，拒绝复用历史通过结果，检查服务端事件，结束时重启应用清除表单 |
| `tests/ssh-gui/config.py` | 共用端口、产物路径与 HDC 调用；错误消息不回显可能含密码的命令或原始输出 |

| 环境变量 | 默认值 | 含义 |
| --- | --- | --- |
| `HDC` | `hdc` | 可执行文件路径，支持含空格路径；也可放入 PATH |
| `HDC_TARGET` | 不指定 | 单设备可省略；多设备必须指定 `hdc list targets` 中的目标 |
| `SSH_GUI_HOST_PORT` | `23222` | Python 服务监听的宿主机环回端口 |
| `SSH_GUI_DEVICE_PORT` | `2222` | 应用连接的模拟器转发端口 |
| `SSH_GUI_REFUSED_PORT` | `2223` | 不可用端口测试使用，须确认没有其他服务监听或转发 |

端口环境变量需在服务端、驱动两侧保持一致，并相应修改 HDC 映射。仅支持一个服务/测试运行同时使用 `build/ssh-gui/`。

## 运行

先在模拟器安装当前 HAP，确认 `uitest` 可用。此套件会重启 `com.example.har_scp`，请先结束手工操作。

终端一启动服务并保持运行：

```sh
.venv/bin/python tests/ssh-gui/ssh_server.py
```

在终端二配置 HDC（WSL 可将 `HDC` 指向 Windows SDK 的 `hdc.exe`，需 Windows 能访问 WSL 环回服务），再执行：

```sh
export HDC=/path/to/hdc
export HDC_TARGET=127.0.0.1:5555
"$HDC" -t "$HDC_TARGET" rport tcp:2222 tcp:23222
.venv/bin/python tests/ssh-gui/run_scenarios.py
```

Windows PowerShell 使用 `$env:HDC` / `$env:HDC_TARGET` 设置相同变量，并通过 `& $env:HDC ...` 调用。不要覆盖他人已有映射，默认端口被占用时换用空闲端口。

无论成功或失败，终端二执行以下命令删除本次映射，然后在终端一按 Ctrl+C 停止服务：

```sh
"$HDC" -t "$HDC_TARGET" fport rm tcp:2222 tcp:23222
"$HDC" -t "$HDC_TARGET" fport ls
```

合成凭据、模式、匿名服务端事件和结果写入已忽略的 `build/ssh-gui/`。界面布局仅在内存读取，设备端临时布局文件每次读取后删除。不要在测试期间手动打印 `credentials.json`。异常强杀后若留下凭据，先确认旧服务已退出，再删除该文件重启；脚本不自动覆盖既有凭据。

## 场景与限制

7 个场景为登录与主动断开、拒绝指纹、错误密码、服务端关闭、握手取消、不可用端口、切后台断开及回前台。只有本次全部执行通过才输出 `All 7 emulator UI SSH scenarios passed`；失败保留本次已通过的部分结果并以非零状态退出。

测试依赖当前中文页面结构、4 个输入框、按钮文案以及模拟器 uitest 输入支持。滚动坐标按当前布局边界缩放，其他屏幕和系统版本仍需实测。服务端断线检查允许 30 秒观察窗口，结果中记录包含 UI 操作的耗时，不代表即时检测或完整超时验收。此套件不替代 ARM64 真机、系统 OpenSSH、IPv6、Hypium 或完整设备验收。

纯 Native 测试的编译方法仍见 [MVP 验证记录](mvp-validation.md)，编译后使用同一 uv 环境运行：

```sh
.venv/bin/python tests/native/integration.py /path/to/ssh_client_test
```

此前临时脚本的历史测试结果见 [模拟器 SSH 验证](emulator-ssh-validation.md)。

## 本次迁移验证

2026-11-03，uv 0.12.7 / Python 3.12.3 创建并同步 `.venv`，7 项依赖兼容检查通过；迁移后的完整入口在 x86_64 / API 26 模拟器上独立执行 7 个场景全部通过。远端关闭观察耗时约 17.97 秒（含 UI 操作），不能视为即时断线检测。另验证了错误指纹不确认认证、HDC 错误/超时不回显输入内容；测试转发和服务已清理，SIGTERM 自动删除凭据通过。完整记录见 [本次改动](../changes/2026-11-03-03-ssh-gui-uv.md)。
