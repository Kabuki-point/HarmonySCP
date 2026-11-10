# ARM64 与 x86_64 原生构建

`entry/build-profile.json5` 同时启用 `arm64-v8a` 和 `x86_64`，CMake 按 `OHOS_ARCH` 链接 `entry/libs/<ABI>/` 下的静态库。保留原有 ARM64 依赖；x86_64 使用独立构建的 libssh2 1.11.1 / OpenSSL 3.5.4。不要用 Linux glibc 或 Android 库替代 HarmonyOS 库。

## 重建 x86_64 依赖

在 Linux/macOS 安装对应主机的 HarmonyOS native SDK、Python 3、Perl、Make、CMake 和 curl，执行：

```sh
OHOS_NDK_HOME=/path/to/sdk/default/openharmony/native bash scripts/build-x86_64-deps.sh
```

脚本下载固定版本源码并检查 SHA256，在忽略的 `build/x86_64-deps/` 中构建，将两个静态库复制到 `entry/libs/x86_64/`。不修改 ARM64 库。默认并行数 4，可用 `JOBS` 调整。Windows 用户可直接使用仓库提供的库在 DevEco 构建；重建脚本要求 Linux/macOS SDK，不能直接传入 Windows SDK。

OpenSSL 使用 `linux-x86_64` 配置加 `--target=x86_64-linux-ohos` 与 SDK sysroot，启用 PIC，关闭汇编、共享库、动态模块和测试。libssh2 使用 SDK CMake toolchain，启用 OpenSSL 后端，关闭示例、测试和 zlib 压缩。不将宿主机库链接进目标库。

## 构建与设备检查

按 [项目说明](../project.md) 执行 `assembleHap`。在 HAP ZIP 中应同时包含 `libs/arm64-v8a/libentry.so` 和 `libs/x86_64/libentry.so` 及对应 C++ 运行库。

```sh
hdc list targets
hdc shell param get const.product.cpu.abilist
hdc install entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell aa start -a EntryAbility -b com.example.har_scp
```

多设备连接时先用 `hdc -t <target>` 指定目标。模拟器能安装、启动不代表 SSH 登录通过；真实网络登录、主机指纹确认、认证、取消及断开仍按 [MVP 清单](mvp-validation.md) 验收。ARM64 真机也须单独回归。

## 宿主机集成测试环境（Windows / MSYS2）

`tests/native/` 的 C++ 测试程序需要宿主机 libssh2 与 **POSIX 头文件**。Windows 上不可使用纯 MinGW 工具链（缺少 `arpa/inet.h`、`sys/socket.h`、`poll.h`），应使用 MSYS2 的 msys 层工具链。

```sh
# MSYS2 环境（示例安装路径 C:\\ProgrammingEnv\\msys64）
pacman -Sy
pacman -S --needed gcc libssh2-devel
```

编译与运行（`-std=gnu++17` 必需，严格 `c++17` 会隐藏 `mkstemp`、`fdopen`、`F_DUPFD_CLOEXEC`）：

```sh
g++ -std=gnu++17 -pthread \
  tests/native/ssh_client_test.cpp entry/src/main/cpp/ssh_client.cpp entry/src/main/cpp/sftp_transfer.cpp \
  -Ientry/src/main/cpp -I/usr/include -L/usr/lib -lssh2 -lcrypto -lz -o build/host/ssh_client_test.exe

.venv/Scripts/python.exe tests/native/integration.py build/host/ssh_client_test.exe
```

Windows 主机上的已知限制：

- 创建符号链接需要 `SeCreateSymbolicLinkPrivilege` 或开启开发者模式；未满足时测试脚本会跳过 `sftp` 场景并打印 `SKIP sftp`。
- `/tmp` 不存在，测试程序的本地临时文件路径需指向存在的目录。
- `remote-close` 场景在部分主机的关闭检测较慢，测试把观察窗口放宽到 30 秒。
