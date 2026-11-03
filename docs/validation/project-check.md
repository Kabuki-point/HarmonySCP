> 以下为模板阶段的历史检查。当前 MVP 实现与验证见 [mvp-validation.md](mvp-validation.md)。

# 工程基线检查（2026-11-02）

- ArkTS Stage / Phone 配置、EntryAbility、页面、页面路由及资源存在。
- CMake、napi_init.cpp、libentry.so 类型声明及模块依赖存在；模块名 entry 相互匹配。
- SDK：target 26.0.0，compatible 6.1.1(24)，Native 编译器配置为 BiSheng。
- ABI：arm64-v8a 和 x86_64。后续第三方库必须覆盖启用的 ABI。
- 当前为加法 NAPI 模板，尚未实现 SSH，也未声明 INTERNET。
- signingConfigs 为空；local.properties、IDE 缓存和签名材料不提交。
- 构建及运行结果以本文件后续追加的真实记录为准。

## 本次实际构建

- 使用 DevEco 自带 Node / Hvigor，显式为命令指定 DEVECO_SDK_HOME 和 JAVA_HOME；未修改系统环境。
- 执行 entry 模块 assembleHap，结果 BUILD SUCCESSFUL。
- 输出：entry/build/default/outputs/default/entry-default-unsigned.hap。
- HAP 内含 arm64-v8a、x86_64 的 libentry.so 和 libc++_shared.so。
- 未配置签名，因此输出未签名 HAP；未安装、启动模拟器或真机。
- 编译器报告 gcc-toolchain 参数未使用的警告，本次未导致构建失败。
- 工程保留 Toolchain Default 的 C++ 标准设置；接入 SSH 模块时再显式统一为 C++17。
