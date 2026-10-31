# Clipswain

**随时掌握你的 Paperclip 团队。**

[English](README.md) · [贡献指南](CONTRIBUTING.md) · [隐私](PRIVACY.md) · [安全报告](SECURITY.md) · [MIT 许可](LICENSE)

在手机上管理 [Paperclip](https://github.com/paperclipai/paperclip) 公司：看任务进度、回复并解除 Agent 的阻塞、查看和管理 Agent（形象、汇报关系、指令）。

这是一个社区维护的独立客户端，与 Paperclip AI 和 Apple 没有官方隶属关系。App 以**董事会成员（board user）**身份调用 Paperclip 的 REST API；无需安装服务器补丁。编辑、发布、审批等操作会写入你连接的服务器。

当前提供源码构建；本仓库不提供官方 App Store / TestFlight 安装入口。

当前只整理本地项目，未创建远端仓库或发布渠道。目录与发布准备见 [项目指南](docs/PROJECT.md)。

## 功能

| 页签 | 能做什么 |
| --- | --- |
| 收件箱 | 按时间倒序保留任务事件：阻塞、完成、开始、待评审、重开、取消、创建及其他状态变化；按事件类型与已读／未读筛选，打开事件标为已读，滑动或长按可切换，支持将筛选结果全部标为已读；任务后续变化不移除旧事件。独立「待处理」入口保留当前提问、确认、阻塞、恢复和审批。角标显示已开启类型的未读事件数，每 30 秒刷新 |
| 任务 | 当前工作概览（阻塞 / 评审中 / 进行中 / 未开始，点按筛选）、当前 / 已完成 / 已取消 / 全部、按负责人筛选、搜索、新建任务；概览和筛选计数遵循相同的负责人及搜索范围，历史按结束时间排序；每项显示总历时，运行中显示本次运行时间 |
| 任务详情 | 总历时、关联运行累计、时间线 / 讨论切换；时间线展示状态变化、每次运行及重试、交互、文档和依赖事件，可跳到运行日志；改状态 / 优先级 / 负责人 / 标题；父任务路径、子任务进度、依赖关系；讨论串（Markdown）；**需要你处理**区域：回答 Agent 的结构化提问、接受 / 拒绝确认、挑选建议任务、多选确认、逐项评审、处理恢复动作（重试 / 标记完成 / 误报）；底部回复框：「回复并继续」会解除阻塞并唤醒 Agent，长按可选「仅回复」或「打断当前运行」；Agent 运行时每 6 秒刷新，并可跳到实时输出 |
| Agents | Paperclip 角色形象画廊（姿态随状态变化：工作中、困惑、休息…）和组织架构树；每 8 秒刷新状态，与详情页共用状态缓存；招聘新 Agent（名字、头衔、角色、上级、能力、运行环境与模型、预算、形象） |
| Agent 详情 | 暂停 / 恢复 / 立即运行 / 清除错误 / 终止（二次确认）；运行环境、模型、心跳、预算；汇报关系与下属；当前任务；最近运行（可看事件和 stdout/stderr 输出，运行中可停止）；技能；编辑名字、头衔、角色、能力、预算、形象配色 |
| 指令 | 查看 Agent 的指令包（AGENTS.md 等），渲染 Markdown 或看原文，可直接编辑保存（带版本基线，避免覆盖别人的修改） |
| 审批 | 查看内容，批准 / 要求修改 / 拒绝，评论 |
| 统计（设置内） | 近 7 / 14 天的交付回顾与趋势、主任务 / 全部任务范围、创建到完成的中位历时与 P90、长耗时任务、负责人交付分布；公司运行区分成功 / 重试恢复 / 未恢复失败；本月已记录费用 |
| 设置 | 切换公司、后台提醒开关、服务器信息、断开连接 |

### 任务结果与交付物

- 在任务详情顶部打开「结果与交付物」。文档列表优先显示 `report`，支持阅读 Markdown 正文、版本和更新时间，并可分享正文；同任务文档链接直接在 App 内打开。研究稿中的表格可横向滚动，也可用「查看列」直接定位右侧列。
- 附件使用当前连接的凭证下载后在系统预览中打开，可使用系统分享功能；网页、PR 等交付链接可直接打开。服务器或 Agent 机器上的本地路径不能作为 iPhone 文件打开，需先由任务上传为附件。
- 三类接口独立显示空状态或错误，可下拉刷新；不支持接口的旧服务器会显示错误，不会误报没有结果。此入口只读取已经保存的内容；未保存为文档的 Agent 回复仍在「讨论」，原始执行输出在「时间线 → 运行 → Output」。

### 提醒与跳转

- 打开「设置 → 后台提醒」后，iOS 会不定期在后台唤醒 App 检查任务历史及 attention feed，按收件箱开启的事件类型发本地通知，并保留提问、审批、运行失败等待处理提醒。两类提醒分别去重；同一次阻塞／待评审只提醒一次，历史读取失败时可用 attention 提醒兜底，历史恢复后也不会为同一次变化再提醒。
- 通知投递不改变已读状态；点击事件通知会校验来源服务器与账号，切到原公司后标记对应事件已读并打开任务。旧版通知通过服务器核实任务所属公司及活动 ID。首次导入旧历史不会补发旧通知，前台已同步的事件也不会重复提醒。
- URL scheme：`clipswain://issue/<任务 id>`、`clipswain://approval/<审批 id>`，可用于快捷指令。

### Siri 与快捷指令发布任务

- App 提供「发布任务 / Publish task」动作，以及「用 Clipswain 发布任务」「用 Clipswain 创建任务」App Shortcuts（英文 Siri：`Publish a task in Clipswain` / `Create a task in Clipswain`）。Siri 会询问任务内容，后台发布后播报真实任务编号及标题，不打开 App。
- 先在 App 中连接服务器并选择公司。动作每次读取保存的连接和所选公司，不依赖前台页面；公司已不可用或执行中连接发生变化时停止，不改投其他公司。
- 默认启用「使用 AI 助手」：已配置时复用现有模型，整理标题、描述、负责人和优先级，并在描述中保留原始口述内容。未配置时直接保存文字，默认中优先级、todo、未分配负责人；也可在快捷指令中关闭 AI。已配置 AI 但生成失败时不会静默发布未分配任务。
- 在「快捷指令」新建一条快捷指令，添加 Clipswain 的「发布任务」，将任务内容设为「每次询问」。用 Siri 说出快捷指令名称即可输入。动作输出任务编号，供后续步骤使用。
- 动作声明允许锁屏、仅后台执行。仍需系统允许锁屏使用 Siri，重启后先解锁一次，且服务器与模型网络可用。首次系统权限提示需先处理。真正的锁屏语音交互须在物理 iPhone 上验证，镜像操作或模拟器测试不能代替。
- 发布 POST 不自动重试；若响应中断或服务器结果不明确，会提示先检查任务列表再重试，避免重复建任务。

### 收件箱筛选与历史

- 右上角筛选按钮可选择事件类型，以及全部／未读／已读。关闭类型会隐藏记录并停止该类后台提醒；重新开启可查看保留的历史，不会补发历史提醒。
- 每个事件使用服务器活动 ID；同一任务多次阻塞会保留多条事件。逐任务读取真实活动历史，补齐离线期间的状态变化；后续仅重读发生变化的任务，同时最多 4 个历史请求。
- 事件、筛选和已读状态按服务器、账号、公司保存在此设备的 Application Support 中，原子写入；刷新、重启、解除阻塞或重新打开任务不会删除记录。当前不跨设备同步，卸载 App 会移除本地存储。
- 「待处理」展示当前仍需处理的事项，可以继续进入任务和审批；它与保留历史的事件列表分别展示。
- 收件箱筛选中的「提问、审批和失败提醒」默认开启，可单独关闭这类后台提醒；阻塞／待评审仍遵循对应事件类型开关。

## 语言与本地化

支持简体中文和英语，默认跟随 iOS 的 App 语言，英文作为回退语言。在 App「设置 → 语言」直接选择跟随系统、简体中文或英语，立即生效并记住选择。语言设置不改变任务内容、服务器地址或 API Key。

App 使用原生 String Catalog，PaperclipKit 使用独立的原生 `.lproj` 资源；添加第三种语言只需补齐资源和语言声明。开发流程与检查命令见 [本地化指南](docs/LOCALIZATION.md)。

## 连接服务器

1. 打开 App，填服务器地址。连接页默认填写 HTTPS，地址必须包含 `https://` 或 `http://`；请填写服务器的最终地址。需要连接明文 HTTP 的局域网、loopback 或 Tailscale 地址时，必须显式允许不安全连接；HTTP 会明文发送 API Key、任务和回复。模拟器的 `127.0.0.1` 指向运行模拟器的 Mac，真机请使用电脑实际可达的地址。
2. 点「检测服务器」，App 会读取部署模式：
   - **本地信任（local_trusted）**：直接连接，无需凭据。
   - **需要登录（authenticated）**：
     - **浏览器批准**：和 `paperclipai` CLI 登录同一流程。App 申请一个待批准的 Board API Key，在弹出的页面登录并批准后自动连接。
     - **粘贴 Board API Key**。
3. Key 保存在本机钥匙串。「断开连接」会尝试撤销服务器上的当前 Key，再结束本地会话；撤销失败时会明确提示，本地退出不代表服务器 Key 已失效。如果本机 Key 删除失败，连接设置会保留并显示错误，需解锁后重试。该操作不清除已保存的事件历史、服务器地址或独立配置的 AI Key。详见[隐私说明](PRIVACY.md)。
4. API、附件和 AI 请求不自动跟随重定向。反向代理应直接在填写的最终地址提供 API，不能依赖 HTTP → HTTPS 或其他 3xx 跳转转发凭据。

> 注意：`pnpm dev` 默认只监听 loopback。要让手机连上，需要 `pnpm dev --bind lan` 或 `--bind tailnet`（会启用登录）。

## 后端兼容范围

本项目使用 Paperclip REST API。2026-10-23 对官方源码 `0fb152ee9493075354fbe9b813c7f2f256f22a52` 做过路由核对：CLI 登录、attention、interactions、recovery、skills、instructions-bundle、documents、attachments 和 work-products 均存在。这不是对所有官方发行版本的兼容承诺，也不等同于在该 commit 上完成端到端测试；目前没有经过验证的最低服务器版本。

| 功能 | 需要的接口 / 不支持时的行为 |
| --- | --- |
| 登录 | `/api/health`、`/api/cli-auth/*`；认证服务器需要 Board API Key 或浏览器批准 |
| 任务、Agent、审批 | `/api/companies/*`、`/api/issues/*`、`/api/agents/*`、`/api/approvals/*` |
| 待处理与结构化回复 | attention、interactions、recovery-actions；attention 不可用时可退回阻塞任务与审批，其他操作可能显示错误 |
| 指令与技能 | Agent 的 skills、instructions-bundle 接口 |
| 结果与交付物 | documents、attachments、work-products；各接口独立显示错误，不把“不支持”当成空列表 |

提交兼容性问题时请附服务器版本或 commit、失败的接口和脱敏错误，不要附 Token、公司内容或完整运行日志。

## AI 助手集成

启用 AI 起草会把输入文字，以及用于分配任务的公司名称、Agent ID / 名称 / 职责 / 能力、父任务标题（如有）发送给所选模型服务。仅使用手动新建任务不需要 AI Key。服务商的留存规则由其政策决定，详见[隐私说明](PRIVACY.md)。

「设置 → AI 助手」可选择 **OpenCode Go** 或 **OpenRouter**：填写该服务的 API Key，
从自动获取的模型列表中选择模型。列表支持按名称、模型 ID 和多个关键词搜索，以及下拉刷新；
网络错误可重试，空列表和无匹配结果会分别提示。地址和协议由 App 配好；列表保留支持文字输出的模型（包括多模态模型），排除仅输出图片等非文字模型和异步 batch 变体。

- OpenCode Go 自动发送真实客户端标识和 `x-opencode-session`；同一个新建任务中的重新生成沿用同一个会话 ID。
- Go 根据模型系列使用 Chat Completions、Messages、Responses 或 Gemini Generate Content 接口。
- OpenRouter 使用模型目录提供的结构化输出能力；不支持时要求返回 JSON，并在本地验证任务字段。
- 两个集成的 Key 分开保存在钥匙串，切换服务会恢复各自配置。旧的手填 Go/OpenRouter 配置会自动迁移。
- 仍保留 Anthropic 和 OpenAI 兼容自定义接口。「测试连接」只用一条示例请求，不创建服务器任务。

接口依据：[OpenCode Go](https://opencode.ai/v2/docs/console/go/)、[OpenRouter 模型目录](https://openrouter.ai/docs/api/api-reference/models/get-models)。
只读目录集成测试：`PAPERCLIP_TEST_MODEL_CATALOGS=1 swift test --package-path PaperclipKit`。
App 的凭据迁移与异步状态回归测试见下方 Simulator 测试命令。

## 项目结构

```text
project.yml              XcodeGen 工程定义（iOS 17+）
Config/                  xcconfig；Local.xcconfig 放签名 Team（不进 Git）
PaperclipKit/            Swift Package：模型 + API 客户端（可在 macOS 上 swift test）
  Sources/PaperclipKit/
    Models/              Issue、Agent、Interaction、Approval、Attention…（未知枚举值不会解码失败）
    API/PaperclipClient  所有 REST 调用
  Tests/                 用真实服务器响应录制的 fixture 做解码测试；LiveServerTests 可连真服务器
App/
  Core/                  AppModel（会话、公司、Agent 缓存）、Keychain、导航路由
  Connect/               连接与登录
  Inbox/                 待处理、审批
  Tasks/                 任务列表、详情、交互卡片、恢复卡片、回复框
  Agents/                画廊、组织架构、详情、编辑、指令、运行详情
  Components/            头像加载、状态徽章、Markdown、自动刷新
Resources/               图标与颜色
```

## 构建与测试

需要 macOS、完整 Xcode（含 iOS Simulator）、XcodeGen 2.46.0 和 Python 3。App 运行最低 iOS 17，但使用 iOS 26 SDK 的 API，因此编译需要 Xcode 26 或更高版本。已在 Xcode 27.0 / Swift 6.4 / XcodeGen 2.46.0 上本地验证。CI 使用 GitHub `macos-26` runner 的 Xcode 26.6；工作流是否通过以实际 Actions 结果为准。

首次安装和选择工具链（命令会安装 XcodeGen、选择已安装的 Xcode）：

```bash
brew install xcodegen
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
xcodegen --version
```

生成工程并构建无需签名的 Simulator App：

```bash
xcodegen generate
xcodebuild -project Clipswain.xcodeproj -scheme Clipswain \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

离线测试和本地化检查（不需要 Paperclip 服务器或真实 Key）：

```bash
python3 scripts/check-localizations.py
python3 scripts/check-public-materials.py
swift test --package-path PaperclipKit
python3 scripts/verify-task-result-downloads.py
python3 scripts/verify-network-security.py
```

运行 App tests：先列出本机已安装的模拟器，再把下方占位符替换为该设备的 UDID。无需固定某一款 iPhone。

```bash
xcodebuild -project Clipswain.xcodeproj -scheme Clipswain -showdestinations
xcodebuild -project Clipswain.xcodeproj -scheme Clipswain \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO \
  -only-testing:ClipswainAppTests test
```

`swift test` 默认跳过真实服务器、模型目录以及需要 localhost fixture 的测试；两个网络验证脚本会单独运行使用假凭据的 localhost fixture。真实服务器测试仅用于**可丢弃的测试实例**：设置 `PAPERCLIP_TEST_URL` 后，会在第一个公司里创建任务、评论、取消任务，并创建登录 challenge。认证实例还需要 `PAPERCLIP_TEST_TOKEN`。不要把这些变量配置到普通 PR CI，也不要使用生产服务器。

```bash
PAPERCLIP_TEST_URL=http://127.0.0.1:3100 swift test --package-path PaperclipKit
```

上面的 `CODE_SIGNING_ALLOWED=NO` 命令用于编译和自动测试。实际验证 Board / AI 凭据保存时，需要带有效 App ID 权限的签名构建；缺少权限的模拟器构建可能返回钥匙串错误 `-34018`。

真机签名：仅当文件尚不存在时，复制 `Config/Local.xcconfig.example` 为 `Config/Local.xcconfig`，填写你自己的 `DEVELOPMENT_TEAM` 和唯一 `APP_IDENTIFIER`。不要覆盖已有本地配置，也不要将证书、签名 Team 私有配置或凭据提交到 Git。`Local.xcconfig` 与生成的 Xcode 工程均被忽略。

独立使用 PaperclipKit 时，Package 声明 Swift tools 5.10、macOS 14 / iOS 17；App 的 SDK 要求仍以上述说明为准。

## 已知限制

- 没有服务器推送（APNs）：前台靠轮询（任务详情 6–20 秒、任务列表 30 秒、Agent 列表 8 秒），后台提醒的频率由 iOS 决定，可能是几十分钟一次。
- 不能改运行环境的详细配置或管理技能，这些仍在网页端做。
- `connection_intent`（连接授权）类交互需要在网页端处理。
- 为支持用户明确允许的自托管 HTTP 地址，ATS 保留 HTTP 例外；应用层要求显式允许。HTTP 不提供传输加密。
- 锁屏 Siri、系统后台唤醒、通知投递以及最低 iOS 版本的实际表现仍需物理设备验证，Simulator 单测不代表这些系统端到端验证。

## 许可与贡献

原创代码采用 [MIT License](LICENSE)。Paperclip 上游配色数据的版权与完整许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。商标及第三方服务不因代码许可而授予使用权。参与方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，变更记录见 [CHANGELOG.md](CHANGELOG.md)。
