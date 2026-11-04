# Native 依赖记录

首版复用用户提供的本地 CrossShellNext `entry/libs` 的 ARM64 静态库及 libssh2.h；未复制其业务代码。
来源参考：https://gitcode.com/OpenHarmonyPCDeveloper/CrossShellNext （由本地参考仓库 origin 核实）。本地来源路径为 Desktop/CrossShellNext；许可证副本见 licenses/CrossShellNext-LICENSE.txt。

| 文件 | 版本证据 | SHA256 |
| --- | --- | --- |
| libssh2.a | 配套头文件 1.11.1；二进制来源 commit 未提供 | 7821df2d22a9bf928dfba53906cb4ed7b2848e49b4fc5f2c678725192b6587be |
| libcrypto.a | 二进制字符串及配套头文件均为 OpenSSL 1.1.1x-dev | ca673b78c2cfe8e489a2f9418cc77b4e8673872bea4713eee8cf8ef47a3ddef4 |

本地参考仓库 revision：`7a8251d121bb0914e63a454fff8ecd8be6d5348a`；其仅有构建配置本地变更。这记录了复制时的参考版本，不能替代静态库实际构建来源证明。

以上为保留的 arm64-v8a 依赖。z 使用 HarmonyOS SDK 系统库，不额外打包 libssl。

libssh2 使用 BSD-3-Clause，见 licenses/libssh2-COPYING.txt，官方源码：https://libssh2.org/download/libssh2-1.11.1.tar.gz 。
OpenSSL 1.1.1 使用 OpenSSL / SSLeay 双许可证，完整文本见 licenses/OpenSSL-LICENSE.txt，文本取得自：https://raw.githubusercontent.com/openssl/openssl/OpenSSL_1_1_1-stable/LICENSE 。

这是课程 MVP 的预编译依赖，未声称其完成安全补丁审计。确切源代码 commit、编译参数、补丁和供应链尚待核实。正式发布前应从受支持的源代码版本可复现构建 SSH/加密依赖，重新完成 ARM64 设备测试和许可证审核。

API 依据：https://libssh2.org/libssh2_session_handshake.html 、https://libssh2.org/libssh2_hostkey_hash.html 。

## x86_64 模拟器依赖（2026-11-03）

从官方未修改源码交叉构建，不复用宿主机 Linux/Windows 或 Android 库。版本固定用于构建复现，不代表已完成安全补丁审计。

| 源码 | 来源 | 下载包 SHA256 |
| --- | --- | --- |
| libssh2 1.11.1 | https://libssh2.org/download/libssh2-1.11.1.tar.gz | d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7 |
| OpenSSL 3.5.4 | https://github.com/openssl/openssl/releases/download/openssl-3.5.4/openssl-3.5.4.tar.gz | 967311f84955316969bdb1d8d4b983718ef42338639c621ec4c34fddef355e99 |

OpenSSL 哈希已对照官方同名 `.sha256` 文件；libssh2 哈希为本次官方站点下载包实测，未进行发布者 PGP 签名验证。共用的 `libssh2.h` 与官方 1.11.1 源码逐字节一致。

| 文件（entry/libs/x86_64/） | SHA256 |
| --- | --- |
| libcrypto.a | 0a1fa1cd1143d3788495412bcf4668aaec836a7adca75d3d579abd07954ba962 |
| libssh2.a | c49f9b53aa0e8105fa8c78783ebeb045e80131c0350c7d016fc7fbf0b3cfc5a4 |

实际工具链：Windows DevEco SDK Native `26.0.0.105`、OHOS Clang `15.0.4`（revision `00dcd9ccdb860908f60ff11b32239084b0908a08`），通过 WSL 路径适配器调用；目标 `x86_64-linux-ohos`，SDK sysroot，PIC。OpenSSL 配置 `linux-x86_64 no-shared no-module no-tests no-asm no-makedepend`，`make build_libs`；libssh2 CMake Release / OpenSSL 后端，关闭共享库、示例、测试、zlib 压缩，并实际交叉链接检测特性。目标应用使用 C++17。

OpenSSL 3.5.4 为 Apache-2.0，完整文本来自源码包 `LICENSE.txt`，见 [OpenSSL-3.5-LICENSE.txt](licenses/OpenSSL-3.5-LICENSE.txt)；ARM64 的旧 OpenSSL 许可证继续保留。libssh2 许可证同上。

重建脚本与参数见 [原生构建说明](../docs/validation/native-dependencies.md)。脚本面向 Linux/macOS SDK；不同主机、归档工具和构建路径可能产生不同二进制哈希，尚未验证逐字节可复现性。两种 ABI 的 OpenSSL 主版本不同，不跨 ABI 混用依赖；算法兼容性与真实 SSH 登录仍需分别验收。

## SFTP 头文件（2026-11-04）

`entry/libs/include/libssh2_sftp.h` 直接取自上表中已校验 SHA256 的官方 libssh2 1.11.1 源码包。文件 SHA256 为 `b5d864f19af69521278ed953b20b76a32cfdc08014da81d38f59964e7e2e2575`，保留原 BSD-3-Clause 许可证声明。此头文件共用于两种 ABI；`nm` 确认两份现有 `libssh2.a` 均提供所需的 SFTP 符号。静态库未替换，ARM64 归档的确切源码版本、补丁和构建过程仍待核实。
