# 填写软件领域调研与需求构思文档

- 日期：2026-11-03（Asia/Shanghai）
- 执行者：Kimi（本会话）
- 关联：无

## 需求与目的

用户要求根据对项目的理解，填写课程模板《1. 软件领域调研与需求构思模板.docx》（来源 D:\download，已按要求复制到仓库根目录操作，原件未改动），形成 HarmonySCP 项目的领域调研与需求构思文档。

## 具体操作

- 使用 kimi-word 技能的 working-copy 流程（prep → 编辑 work/unpacked → opc pack → verify --baseline）填写模板，输出 `HarmonySCP软件领域调研与需求构思.docx`（仓库根目录）。
- 封面：项目名填为“HarmonySCP——鸿蒙安全文件传输客户端”（红色占位样式改为黑色），编制日期填为 2026 年 11 月 3 日；成员姓名、学号、贡献占比因信息未知保留空白，待用户填写。
- 变更历史表第 2 行：初始版本记录（2026-11-03，V1.0，变更人员写“全体成员”）。
- 七个章节按模板提示填写，内容依据 docs/project.md、docs/validation/mvp-validation.md 与已有改动记录：背景介绍、欲解决问题、领域内相关软件对比（新增 7×5 对比表：PuTTY、OpenSSH、WinSCP、Xshell/Xftp、Termius、JuiceSSH/ConnectBot）、软件创意、系统组成和部署、功能描述、可行性及潜在风险。
- 正文使用宋体 12pt、两端对齐、首行缩进；settings.xml 增加 updateFields，使 Word 打开时刷新目录页码。
- 编辑脚本保留在仓库根目录 `fill_doc.py`；中间产物在 `work/`（unpacked、baseline.docx、view.txt）。

## 验证

- `verify.py --baseline`：PASSED（13 个部件 XSD 与语义检查通过）；语义差异逐项核对，均为本次预期改动，无意外改动。
- 视觉渲染检查未能执行：docx.py render 需要 node，本机 PATH 中的 node 为 shell 封装脚本，CreateProcess 无法直接调用，两次尝试均失败（FileNotFoundError）；按流程不重试，文档以结构验证为准交付。

## 限制与风险

- 目录页码为模板缓存值，需在 Word/WPS 中打开后刷新（已设置 updateFields，打开时会提示更新）。
- 成员姓名、学号、贡献占比留空；“变更人员”一栏暂写“全体成员”，可由用户改为具体姓名。
- 第 3 章对比表中同类软件的功能与授权信息为公开常识性描述，未逐条联网核实最新版本。
- 文档在仓库根目录未跟踪；`work/`、`fill_doc.py`、`qa-render/`（空目录）为过程产物，可按需删除或忽略。

## 后续事项

- 用户补填成员信息并按需调整贡献占比。
- 如需提交，确认是否将成品文档与过程产物纳入版本控制。
