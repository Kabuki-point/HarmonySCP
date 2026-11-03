# Native 依赖记录

首版复用用户提供的本地 CrossShellNext `entry/libs` 的 ARM64 静态库及 libssh2.h；未复制其业务代码。
来源参考：https://gitcode.com/OpenHarmonyPCDeveloper/CrossShellNext （由本地参考仓库 origin 核实）。本地来源路径为 Desktop/CrossShellNext；许可证副本见 licenses/CrossShellNext-LICENSE.txt。

| 文件 | 版本证据 | SHA256 |
| --- | --- | --- |
| libssh2.a | 配套头文件 1.11.1；二进制来源 commit 未提供 | 7821df2d22a9bf928dfba53906cb4ed7b2848e49b4fc5f2c678725192b6587be |
| libcrypto.a | 二进制字符串及配套头文件均为 OpenSSL 1.1.1x-dev | ca673b78c2cfe8e489a2f9418cc77b4e8673872bea4713eee8cf8ef47a3ddef4 |

本地参考仓库 revision：`7a8251d121bb0914e63a454fff8ecd8be6d5348a`；其仅有构建配置本地变更。这记录了复制时的参考版本，不能替代静态库实际构建来源证明。

仅启用 arm64-v8a。z 使用 HarmonyOS SDK 系统库，不额外打包 libssl。

libssh2 使用 BSD-3-Clause，见 licenses/libssh2-COPYING.txt，官方源码：https://libssh2.org/download/libssh2-1.11.1.tar.gz 。
OpenSSL 1.1.1 使用 OpenSSL / SSLeay 双许可证，完整文本见 licenses/OpenSSL-LICENSE.txt，文本取得自：https://raw.githubusercontent.com/openssl/openssl/OpenSSL_1_1_1-stable/LICENSE 。

这是课程 MVP 的预编译依赖，未声称其完成安全补丁审计。确切源代码 commit、编译参数、补丁和供应链尚待核实。正式发布前应从受支持的源代码版本可复现构建 SSH/加密依赖，重新完成 ARM64 设备测试和许可证审核。

API 依据：https://libssh2.org/libssh2_session_handshake.html 、https://libssh2.org/libssh2_hostkey_hash.html 。
