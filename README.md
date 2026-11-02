# Har_SCP

HarmonyOS 手机端 SSH 客户端课程项目。当前仓库为 DevEco Studio Native C++ 模板基线，尚未实现 SSH。

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
