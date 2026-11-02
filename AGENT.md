# Har_SCP 项目进度与交接记录

更新时间：2026-11-02（Asia/Shanghai）。本文件集中记录项目范围、环境、真实进度和下一步任务。

HarmonyOS 手机端 SSH 客户端课程项目。当前仓库为 DevEco Studio Native C++ 模板基线，尚未实现 SSH。

## 当前进度

- [x] 创建 DevEco Studio Native C++ 手机工程，检查 Stage、页面、Ability、资源、NAPI 注册和类型声明。
- [x] 阅读本地 CrossShellNext 和 FtpNextClient 实际源码，确认主参考项目连接流程耦合终端/SFTP，主机密钥验证需补充。
- [x] 在独立临时目录验证参考项目 libssh2.a + libcrypto.a + z 可由 Native SDK 链接成 ARM64 .so；未将其导入本工程。
- [x] 初始化 Git，创建私有 GitHub 仓库并推送 main：https://github.com/mullen0612/Har_SCP。
- [x] 补充忽略规则、PR 模板和工程检查记录；不提交本机路径、缓存、构建产物和签名材料。
- [x] 使用 DevEco 自带 Hvigor 执行 entry 模块 assembleHap，结果 BUILD SUCCESSFUL。
- [x] 检查未签名 HAP，含 arm64-v8a、x86_64 的 libentry.so 和 libc++_shared.so。
- [ ] 邀请团队协作者，统一 SDK、模拟器镜像和 ABI。
- [ ] 在手机模拟器运行模板，确认 ArkTS 调用 Native 示例成功。
- [ ] 整理第三方库来源、版本、安全补丁、许可证及目标 ABI。
- [ ] 实现 SSH 连接、主机身份验证、密码认证、状态机、取消和断开。
- [ ] 执行第一阶段完整验收测试。

模板基线首次提交为 262afbc。构建成功不代表模拟器运行或 SSH 登录成功；当前没有完成这些运行验证。

## 第一阶段范围

- SSH 连接、服务器主机密钥验证、用户名和密码认证。
- 连接状态展示、连接中取消、主动断开。
- 暂不实现终端、命令执行、SFTP 和文件传输。

## 开发环境

| 配置 | 当前值 |
| --- | --- |
| DevEco Studio | 26.0.0.865 |
| SDK | HarmonyOS 26.0.0，API 26 |
| 最低兼容版本 | HarmonyOS 6.1.1，API 24 |
| 应用模型与设备 | Stage / Phone |
| Bundle name | com.example.har_scp |
| Native 编译器 | BiSheng（工程配置） |
| 目标 ABI | arm64-v8a、x86_64 |

## 打开与构建

1. 克隆仓库，在 DevEco Studio 打开仓库根目录。
2. 安装相应 HarmonyOS SDK 和 Native 工具，配置各自本机 SDK 路径。
3. 等待 OHPM / Hvigor 同步，构建 entry 模块。
4. 使用满足最低 API 要求的手机模拟器；先点击模板页面，检查 HiLog 中的 NAPI 加法结果。
5. 真机调试由成员各自配置签名。不要提交个人签名材料或含凭据的配置。

模拟器运行和 SSH 验收尚未完成。当前模块尚未声明 INTERNET 权限，将在接入网络功能时添加。

## 团队协作

- main 保存完成相应验证的集成版本；从最新 main 创建 feat/*、fix/* 或 docs/* 分支。
- 一个任务对应一个 Issue，注明负责人和验收条件。
- 通过 Pull Request 合并，至少由另一位成员审查；建议 Squash merge。
- 共享构建配置、源代码和依赖锁文件；本机路径、缓存、构建产物、密码和签名材料不入库。
- 未经实际执行，不将构建成功写成模拟器运行或 SSH 登录成功。

## 目录

- AppScope：应用元数据与资源。
- entry/src/main/ets：ArkTS 页面与 Ability。
- entry/src/main/cpp：C++ NAPI 示例、CMake 与接口类型。
- entry/src/test、entry/src/ohosTest：模板测试。
- docs：工程检查和测试记录。

参考项目代码和第三方 SSH 库尚未复制入本仓库；引入时将补充版本来源和许可证声明。

## 构建验证与限制

- 目标 API 26，最低兼容 API 24；没有验证 HarmonyOS 5.0 设备兼容性。
- 工程 Native 编译器配置为 BiSheng，当前 C++ 标准保持 Toolchain Default；接入 SSH 时再明确统一为 C++17。
- 通过仅作用于构建命令的 DEVECO_SDK_HOME、JAVA_HOME 和 PATH 指定 DevEco 自带环境，未修改系统环境变量。
- 输出 entry/build/default/outputs/default/entry-default-unsigned.hap，未配置签名，未安装到模拟器或真机。
- 本次有 gcc-toolchain 参数未使用的编译警告，未导致构建失败。
- 详细基线检查见 docs/project-check.md；后续变更在本文件持续更新进度。

## 下一步

1. 团队成员接受仓库邀请并克隆，确认工程可以同步与构建。
2. 负责运行的成员创建满足 API 要求的 Phone 模拟器，记录镜像版本、ABI 和模板运行结果。
3. 统一 SSH 状态、错误码、首次指纹确认和 NAPI 接口，再分配页面与原生模块任务。
4. 引入已核实的原生依赖并实现第一阶段功能；网络功能加入时声明 INTERNET 权限。
