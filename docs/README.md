# 项目文档

根目录 [AGENTS.md](../AGENTS.md) 是 agent 工作入口；根目录 README 按约定保留空白。

## 项目与验证

- [项目范围、开发环境、构建与使用](project.md)
- [模板阶段基线检查（历史）](validation/project-check.md)
- [MVP 验证、复现步骤及设备验收](validation/mvp-validation.md)
- [双 ABI 原生依赖重建与安装检查](validation/native-dependencies.md)
- [x86_64 模拟器 SSH 功能验证](validation/emulator-ssh-validation.md)
- [SSH GUI 脚本运行与 uv 环境](validation/ssh-gui-testing.md)
- [SFTP 单文件传输验证](validation/sftp-validation.md)
- [第三方依赖来源与许可证](../third_party/NOTICE.md)

## Agent 改动记录

按任务新增文件，按时间和同日序号排列；具体要求见根目录 AGENTS.md。

- [2026-11-02 / 01：实现 SSH 登录 MVP](changes/2026-11-02-01-ssh-mvp.md)
- [2026-11-02 / 02：排查预览器登录与修复重试输入](changes/2026-11-02-02-preview-and-retry.md)
- [2026-11-02 / 03：整理文档规范并准备仓库交付](changes/2026-11-02-03-documentation-layout.md)
- [2026-11-02 / 04：更新约束描述与指定分支交付](changes/2026-11-02-04-remote-handoff.md)
- [2026-11-03 / 01：增加 x86_64 模拟器构建](changes/2026-11-03-01-x86_64-emulator.md)
- [2026-11-03 / 02：在模拟器验证 SSH 连接功能](changes/2026-11-03-02-emulator-ssh-test.md)
- [2026-11-03 / 03：保留 SSH GUI 测试脚本并使用 uv](changes/2026-11-03-03-ssh-gui-uv.md)
- [2026-11-03 / 04：填写软件领域调研与需求构思文档](changes/2026-11-03-04-requirements-doc.md)
- [2026-11-04 / 01：指定桌面工作区](changes/2026-11-04-01-desktop-workspace.md)
- [2026-11-04 / 02：实现 SFTP 单文件传输](changes/2026-11-04-02-sftp-single-file.md)
- [2026-11-04 / 03：功能分支命名与 DevEco 检查](changes/2026-11-04-03-feature-branch-and-deveco-check.md)
- [2026-11-04 / 04：模拟器验证 SFTP 单文件往返](changes/2026-11-04-04-sftp-emulator-round-trip.md)
- [2026-11-04 / 05：SFTP 远程文件管理](changes/2026-11-04-05-sftp-file-manager.md)
- [2026-11-04 / 06：按团队需求更新需求构思文档](changes/2026-11-04-06-update-requirements-doc.md)
- [2026-11-05 / 01：SFTP 模拟器异常验收（进行中）](changes/2026-11-05-01-sftp-device-acceptance.md)
- [2026-11-05 / 02：Windows x86_64 模拟器验证 SSH 与 SFTP（第一批）](changes/2026-11-05-02-windows-x86-emulator-validation.md)
- [2026-11-05 / 03：按项目进展更新需求构思文档并排除 docx 产物入库](changes/2026-11-05-03-update-requirements-doc.md)
- [2026-11-10 / 01：SSH 公钥认证（第一批：Native 核心与接口）](changes/2026-11-10-01-ssh-key-auth-native.md)
- [2026-11-12 / 01：公钥认证设备端验证尝试与阻塞](changes/2026-11-12-01-emulator-key-auth-attempt.md)
- [新改动记录模板](changes/TEMPLATE.md)
