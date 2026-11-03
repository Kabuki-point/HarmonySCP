# 排查预览器登录与修复重试输入

- 日期：2026-11-02（Asia/Shanghai）
- 执行者：Codex（本会话，依据实际操作补录）
- 关联：用户反馈登录失败，纳入本次代码交付

## 需求与目的

检查 DevEco 日志与代码，定位无法登录的原因，并避免预览限制、表单状态更新造成误导。

## 具体操作

- 实际检查 DevEco：目标为“预览器”、HiLog 无设备；`hdc list targets` 返回空列表，用户确认在预览器中操作。
- `Index.d.ts`、`napi_init.cpp`、`Libentry.mock.ets`：增加 nativeAvailable 标志；Native 返回 true，预览 mock 返回 false 和 preview 状态。
- `Index.ets`：预览状态显示能力限制并禁用登录；只有连接状态切换时清除密码，修复 error 状态每 200ms 反复清空重试输入；相同状态轮询不再覆盖表单校验提示。
- `ssh_client.cpp`、CMake：接入 HiLog，tag 为 HarmonySCP，仅记录状态、错误阶段和错误码，保留主机指纹确认。

## 验证

- Hvigor `assembleHap` 成功，`git diff --check` 通过。
- 同一 Native 连接核心重新执行 6 个本机 SSH 集成场景，全部通过。
- 用户后续反馈“我验证了没问题”；设备和具体测试场景尚未提供，未据此声明完整设备验收通过。

## 限制与风险

agent 未完成设备侧新增日志和预览提示的界面运行验收；当前记录能确认导致用户当时无法登录的直接原因是工程的预览 mock 不发起 SSH。

## 后续事项

需要进一步排错时，在实际设备 HiLog 按 HarmonySCP 筛选 tcp-connect、handshake、password-auth 阶段及错误码。
