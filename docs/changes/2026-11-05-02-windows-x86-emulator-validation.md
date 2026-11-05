# Windows x86_64 模拟器验证 SSH 与 SFTP（第一批）

- 日期：2026-11-05（Asia/Shanghai）
- 执行者：宋广杨（验收负责）、Kimi（agent，自动化执行与记录）
- 关联：本地 `feature/sftp-file-manager`，基于 `261516e`；未提交、未推送

## 需求与目的

用户无 ARM64 真机，需在本机 x86_64 模拟器上验证 `feature/sftp-file-manager` 的功能，接续 [SFTP 验证记录](../validation/sftp-validation.md) 中 11-05 验收表的待验证项。本次为第一批：SSH 全场景与 SFTP 只读/建目录类操作。

## 环境

- Windows 11 + DevEco Studio 26.0.0.865；模拟器 x86_64 / API 26（`const.product.cpu.abilist=x86_64`），屏幕 1280x2832。
- 被测 HAP：`entry-default-unsigned.hap`，由 `261516e` 全量构建（含 arm64-v8a 与 x86_64 双 ABI），SHA256 `8cb674c684b2880af53c5ad85c81c966be3a405fa28b6e28270b3bd00abe26ef`。模拟器免签名 `hdc install` 成功，Native 库正常加载。
- 服务端：`build/sshtest` venv（Python 3.12.16，按根目录 requirements.txt 安装 paramiko 5.1.0）；SSH 场景使用仓库 `tests/ssh-gui/ssh_server.py`；SFTP 场景使用基于 `tests/native/integration.py` 的 SftpFixture 编写的 `build/driver/sftp_server.py`（无人工延迟，写入限定 `build/sftp-root`）。合成账号、随机 RSA 2048 主机密钥、仅监听 127.0.0.1。
- 链路：应用 `127.0.0.1:2222` → `hdc rport` 反向转发 → 本机 `23222` → Paramiko 服务（与 11-03 记录相同的拓扑）。
- UI 驱动：`tests/ssh-gui/` 复制到 `build/driver/` 后适配（仓库代码未改），适配内容见下"测试基础设施问题"。

## 验证结果（agent 自动化实测）

SSH 7 场景（`run_scenarios.py`，全部通过，与服务端事件逐条核对）：

| 场景 | 结果 |
| --- | --- |
| 成功登录与主动断开 | 通过；页面指纹与服务端密钥 SHA256 一致，确认前 0 次认证 |
| 拒绝指纹 | 通过；0 次密码认证请求 |
| 错误密码 | 通过；服务端 1 次认证失败，页面显示连接失败 |
| 登录后服务端关闭 | 通过；页面转为连接失败 |
| 握手阶段取消 | 通过；0 次认证请求，1 秒内回到准备连接 |
| 不可用端口 | 通过；连接失败，服务未收到连接 |
| 切后台断开并回前台 | 通过；服务端连接关闭，回前台为准备连接 |

SFTP（`sftp_server.py` + 合成样本：中文空格名文本、empty.bin、hello.txt、子目录 sub/nested.txt、big-256MiB.bin，SHA256 记录在 `build/sftp-root-hashes.json`）：

| 项目 | 结果 |
| --- | --- |
| 登录后自动列出登录目录 | 通过；页面显示 `/work` 及全部 5 个样本条目 |
| 打开文件夹 / 上一级 / 刷新 | 通过；进入 `子目录 sub` 显示 nested.txt 与正确路径，返回与刷新后列表正确 |
| 新建文件夹 | 通过；`agent测试目录` 出现在列表，服务端确认已创建 |

## 测试基础设施问题（均为模拟器/平台差异，非应用缺陷）

1. **熄屏极快且锁屏即断连**：屏幕锁定使应用退后台，`EntryAbility.onBackground()` 按设计断开 SSH（与 11-05 记录的 Picker 返回断连一致）。`power-shell setmode 602` 无效，最终用 `power-shell timeout -o 1800000` 覆盖熄屏时间。结束前未能恢复（模拟器已关闭），该覆盖为运行时设置，模拟器重启后需复查。
2. **Windows SO_REUSEADDR 语义**：多个测试服务可同时绑定同一端口，连接落到先绑定者，造成"凭据不匹配"假象；两次排查后通过清点进程解决。后续每轮测试前必须清理残留服务进程。
3. **Git Bash 路径转换**：`hdc file send` 的远程路径被 MSYS 转成本地路径，需 `MSYS_NO_PATHCONV=1`；且目标不存在时 hdc 会创建同名目录嵌套存放。另外 shell 用户对 `/storage/media` 与 hmdfs 真实路径均无写权限，上传样本改为"先下载再回传"路线。
4. **UI dump 裁剪**：页面只挂载视口内节点，表单第 4 个输入框常被裁掉；`tests/ssh-gui` 的回顶手势起点 18% 高度在本模拟器会打开控制中心；`uitest inputText` 追加问题沿用既有 Ctrl+A/Delete 方案。驱动副本相应改为：中部起滑回顶、渐进式按视口填表、检测到启动器特征（搜索关键词）时自动唤醒+解锁+回前台。
5. **软键盘遮挡**：文本输入后键盘不收起会拦截后续点击与滚动（一次 Back 误触导致应用退后台断连）。条目选中类操作因此未完成自动化。

## 未完成项（下一批）

按 [SFTP 验证记录](../validation/sftp-validation.md) 11-05 表与远程文件管理清单：重命名、同名冲突、删除空/非空目录（UI 自动化受键盘遮挡阻塞，改人工操作+agent 服务端核对）、下载与 Picker 保存及哈希比对、上传与同名保护、取消传输与临时文件清理、传输中断网/切后台、取消后同会话重试与断连重试。

## 限制与说明

- x86_64 依赖为仓库自带（libssh2 1.11.1 + OpenSSL 3.5.4），非本机另行构建；ARM64 真机路径未验证。
- 本次 SFTP 服务端为 Paramiko 实现的等效服务，与队友使用的系统 OpenSSH 不同；SFTP 子系统行为以仓库集成测试的 SftpFixture 为准，差异未逐项比对。
- 测试产物（venv、驱动副本、样本、结果）均在忽略的 `build/` 下，不入库；凭据为一次性合成，未写入日志或文档。

## 后续事项

- 下一批验证按"用户操作模拟器、agent 核对服务端"分工执行；开始前重新启动模拟器并检查熄屏覆盖与转发规则。
- 两批完成后把结果合并进 `docs/validation/sftp-validation.md`，与队友的 11-05 验收表对齐。
- 模拟器端验证：恢复或确认熄屏时间设置（`power-shell timeout -r`）。
