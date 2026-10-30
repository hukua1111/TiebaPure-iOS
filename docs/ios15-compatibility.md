# iOS 15 适配改造说明

本文记录把 TiebaPure-iOS 的最低支持版本从 **iOS 16.4** 下探到 **iOS 15.0** 所依赖的全部改动：哪些位置用了高版本 API、为什么要改、怎么改、以及每处改动的影响范围。

> 验证前提：本仓库的构建与运行验证仍需要 macOS + Xcode（`xcodegen` + `xcodebuild`）。本次改动是静态改造，未在本机完成编译（环境无 Swift 工具链），第 6 节给出完整的验证步骤。

## 1. 总体结论

- 部署目标：`16.4` → `15.0`（`project.yml`、`TiebaPure.xcodeproj`，构建号 `59` → `60`）。
- 兼容策略：**不改业务逻辑、不改视图结构**，只在系统 API 边界做分支。新增 4 个文件：
  - `TiebaPure/Core/UI/CompatibleNavigation.swift`：`NavigationStack(path:)` 与 iOS 15 的 `NavigationView` 栈实现。
  - `TiebaPure/Core/UI/CompatibleModifiers.swift`：`LabeledContent` / `ShareLink` / `ViewThatFits` / 滚动样式 / 指向性修饰符 / Foundation 兼容件。
  - `TiebaPure/Core/UI/CompatibleImagePicker.swift`：`PhotosPicker` 的 iOS 15 等价实现（`PHPickerViewController`）。
  - `TiebaPureTests/CompatibleNavigationTests.swift`：栈深度回写与延时换算的单元测试。
- 所有兼容件都遵循同一形状：`if #available(iOS 16.0, *) { 原 API } else { 等价旧实现 }`，因此 **iOS 16 及以上与改造前逐字等价**（`LabeledContent`、`ShareLink`、`ViewThatFits`、滚动修饰符在 16+ 全部走原 API）。
- SwiftData（iOS 17）原本就整体包在 `@available(iOS 17.0, *)` 里并弱链接，16.4 时走的就是加密文件后端，**这次无需改动**：iOS 15 与 iOS 16.4 的数据路径完全一致。

## 2. 高版本 API 清单与改造

### 2.1 导航（改动量最大）

| # | 依赖的 API | 引入版本 | 调用位置 | 为什么必须改 | 改造方式 | 影响范围 |
|---|---|---|---|---|---|---|
| 1 | `NavigationStack(path:)` | 16.0 | `ReaderSplitLayout.detailStack`、`ReaderSplitLayout.splitListStack`、`MeView.body` | iOS 15 无此类型，编译失败 | 新增 `CompatibleNavigationStack(path:root:destination:)` | iOS 16+ 仍用 `NavigationStack(path:)`；iOS 15 用 `NavigationView(.stack)` + 每层一个 0 尺寸 `NavigationLink(isActive:)` 复现 path 栈 |
| 2 | `NavigationStack { }`（无路径容器） | 16.0 | `RootView.ExternalRouteView`、`ContentComposerView.body`、`ContentComposerPresentation.draftStateNavigation`、`MeView` 登录 sheet、`UserProfileView` 编辑 sheet、`StandaloneSearchNavigationView`、`SavedSubpostsView`、`SubpostListSheet`（8 处） | 同上 | 新增 `CompatibleNavigationContainer` | 这些位置都只在 sheet / fullScreenCover 内，iOS 15 用单列 `NavigationView`，标题、工具栏、关闭按钮不变 |
| 3 | `.navigationDestination(for:destination:)` | 16.0 | `HomeView`、`ForumHubView`、`MeView`、`ReaderSplitLayout`（4 处） | iOS 15 无值路由 | 目的地闭包从视图链上移到栈参数：`ReaderSplitLayout(listDestination:)`、`CompatibleNavigationStack(destination:)`；`HomeView`/`ForumHubView` 的 `switch route` 原样抽成 `destination(for:)` | 值为 `HomeNavigationRoute` / `ForumHubNavigationRoute` / `MeNavigationRoute` / `ReaderSplitThreadRoute`；iOS 16+ 仍由 `navigationDestination(for:)` 挂载，路由语义不变 |
| 4 | `.navigationDestination(isPresented:)` | 16.0 | 20 处（Home ×2 / ForumThreads ×3 / ForumList / Messages / FollowedUsers / BrowsingHistory / ThreadFavorites / UserProfile ×3 / SearchResults ×3 / ThreadDetail ×4） | iOS 15 无此修饰符 | 改名 `compatibleNavigationDestination(isPresented:)`：16+ 走原 API，15 用隐藏 `NavigationLink(isActive:)` | 行为对齐：push、返回按钮、边缘返回手势、`isPresented=false` 时回写绑定都一致；调用点仅改名 |
| 5 | `NavigationSplitView` | 16.0 | `ReaderSplitLayout.splitNavigation`（iPad 双栏） | iOS 15 无此类型 | iOS 15 用 `HStack { 列表列(固定宽) Divider 详情列 }`，两列各一个 `NavigationView` | iPad 仍为「左列表 + 右详情」双栏；列宽仍由 `ReaderSplitColumnWidthPolicy` 计算 |
| 6 | `.navigationSplitViewColumnWidth` / `.navigationSplitViewStyle` | 16.0 | 同上 | 同上 | 视情况包成 `readerSplitColumnWidth(_:)`；`#available(iOS 16)` 分支保留原修饰符 | iOS 15 由显式 `frame(width:)` 决定列宽，视觉一致 |
| 7 | `NavigationLink { destination } label: { }` | 16.0 | 7 处：`ForumListView`（设置入口）、`SettingsView` ×3、`AboutView` ×2、`SavedThreadsView` ×1 | 该构造器 iOS 16 才有 | 新增 `CompatibleNavigationLink`；15 用 `NavigationLink(destination:label:)` | 仍是 push，返回行为不变 |

**为什么 iOS 15 的栈要自己实现**：`NavigationStack` 是 iOS 16 引入的、以数据驱动的方式管理栈深度的容器；iOS 15 只有 `NavigationView` + `NavigationLink`。改造保留了原有 `[Route]` 路径数组、`HomeNavigationPathPolicy` / `MeNavigationPathPolicy` 等纯函数以及全部测试，只把「路径 → 视图层级」的渲染放到兼容层里：

- 每一层渲染 `path[depth]` 对应的目的地，并挂一个零尺寸 `NavigationLink(isActive:)`；
- `isActive == path.count > depth`，因此路径变深即 push；
- 用户点返回 / 侧滑返回时 NavigationLink 把 `isActive` 置 false，兼容层据此把 path 截断到该层（`CompatibleNavigationPathPolicy.popping(_:toDepth:)`，有单元测试覆盖），等价于 `NavigationStack` 自己回写路径。

### 2.2 布局、表单与分享

| # | 依赖的 API | 引入版本 | 调用位置 | 为什么必须改 | 改造方式 | 影响范围 |
|---|---|---|---|---|---|---|
| 8 | `ViewThatFits` | 16.0 | 8 处：`ContentComposerView.actionBar`、`UserProfileView.identitySummary` / `profileStats`、`SearchResultsView.controls`、`ThreadDetailView` 回复控制栏 / 筛选 / 排序、`ImageViewer.bottomBar` | iOS 15 无此类型 | `CompatibleViewThatFits(preferred:fallback:)` | 16+ 仍做宽度协商；iOS 15 用主（横排）布局，无障碍字号下用紧凑（竖排）布局 —— 见第 3 节 |
| 9 | `LabeledContent` | 16.0 | `AboutView` 4 处（版本、作者、两个许可证） | iOS 15 无此类型 | `CompatibleLabeledContent`（15 用 `HStack` + `Spacer`，值为次要色） | 关于页的「左标题右值」外观不变 |
| 10 | `ShareLink` | 16.0 | `ThreadDetailView` 更多菜单、`SavedThreadsView` 工具栏 | iOS 15 无此类型 | `CompatibleShareLink`（15 用 `UIActivityViewController`，iPad 上设为居中 popover） | 分享面板内容与来源 URL 一致 |
| 11 | `PhotosPicker` / `PhotosPickerItem` / `loadTransferable` | 16.0 | `ContentComposerView.mediaButton`、`preparePhotoSelection` | iOS 15 无此类型，`Transferable` 同样是 16+ | `CompatibleImagePickerButton`：16+ 原样用 `PhotosPicker`，15 用 `PHPickerViewController`（`PhotosUI`，iOS 14 起可用）多选，选中后回调 `[Data]`；两条路径都产出 `CompatiblePickedPhoto`，复用同一套解码与进度逻辑 | 回复贴图的上限（9 张）、进度、失败提示、`isBusy` 禁用条件都不变；15 上选择器以 sheet 呈现 |
| 12 | `.presentationDetents` / `.presentationDragIndicator` | 16.0 | `ThreadDetailView.subpostInteractivePresentation` | iOS 15 无此修饰符 | 三分支：16.4+ 原样；16.0–16.3 原样；15 只保留 `interactiveDismissDisabled()` | iOS 15 的 sheet 本身就是单个 large detent、默认无抓手，视觉等价 |
| 13 | `.presentationBackground(.clear)` | 16.4 | 同上 | 原代码已按 16.4 门控 | 不变 | iOS 15–16.3 本就没有该能力（改造前在 16.0–16.3 也不生效） |

### 2.3 工具栏与滚动样式

| # | 依赖的 API | 引入版本 | 调用位置 | 为什么必须改 | 改造方式 | 影响范围 |
|---|---|---|---|---|---|---|
| 14 | `.toolbar(_:for: .tabBar)` | 16.0 | `HomeView` / `ForumHubView` / `MeView`（`.visible`）、`ThreadDetailView`（`.hidden`） | iOS 15 无此重载 | `compatibleTabBarVisibility(_:)` | iOS 15 忽略该调用（系统无能力），tab bar 在帖子详情页保持可见 —— 见第 3 节 |
| 15 | `.scrollIndicators(.hidden)` | 16.0 | `ContentComposerView` 图片条、表情条 | 同上 | `compatibleHiddenScrollIndicators()`：15 用零尺寸 `UIViewRepresentable` 找到承载的 `UIScrollView` 并关闭指示器 | 纯装饰；查找失败时静默保留默认，不会崩 |
| 16 | `.scrollContentBackground(.hidden)` | 16.0 | `ContentComposerView` 的 `TextEditor`、`ForumHubView` 的 `Form` | 同上 | `compatibleHiddenScrollContentBackground()`：15 把底层 `UIScrollView`（`UITableView`/`UITextView`）背景设为透明 | 让自定义背景透出，与 16+ 观感一致 |
| 17 | `.scrollDismissesKeyboard(.interactively)` | 16.0 | `ContentComposerView` 编辑区 | 同上 | `compatibleInteractiveKeyboardDismissal()`：15 设 `keyboardDismissMode = .interactive` | 拖动收起键盘的手感一致 |
| 18 | `.scrollBounceBehavior(.always, axes: .vertical)` | 16.4 | `HomeView` 信息流 | 同上 | `compatibleAlwaysVerticalBounce()`：15 设 `alwaysBounceVertical = true` | 内容不足一屏时仍可下拉刷新 |
| 19 | `.fontDesign(.monospaced)` | 16.0 | `ImageViewer` 原图按钮（加载中文案宽度稳定） | 同上 | `compatibleMonospacedFontDesign()`：15 不施加（无保字号的等宽入口） | 仅影响「查看原图 xx MB」加载中的字形宽度，见第 3 节 |
| 20 | `ToolbarItemPlacement.topBarLeading` / `.topBarTrailing` | 17.0 | 18 处（Root / Home / ForumThreads / ForumList / About / BrowsingHistory / MeView / ThreadFavorites / UserProfile / SavedThreads / ThreadDetail） | 这两个枚举值是 iOS 17 才改的名，15 只有 `navigationBar*` | 统一改回 `.navigationBarLeading` / `.navigationBarTrailing`（iOS 14 起可用，17 起被标记为弃用但功能相同） | 工具栏位置完全一致 |

### 2.4 输入与 Foundation / 标准库

| # | 依赖的 API | 引入版本 | 调用位置 | 为什么必须改 | 改造方式 | 影响范围 |
|---|---|---|---|---|---|---|
| 21 | `TextField(_:text:axis:)` + `.lineLimit(1...3)` | 16.0 | `ContentComposerView.titleField` | iOS 15 无纵向轴输入框、`ClosedRange` 版 `lineLimit` 也是 16+ | 抽成 `titleField`：16+ 多行 1–3 行；15 单行 `TextField` | 发帖标题在 15 上不换行，见第 3 节 |
| 22 | `Duration` + `Task.sleep(for:)` | 16.0 | `ForumSignCoordinator.requestSpacing`、`ShortPullRefresh`（650ms）、`ThreadDetailView`（1500ms 超时、`ThreadReadingPersistencePolicy.idleDelay` 250ms） | `Duration` 本身是 16+，`sleep(for:)` 一并不可用 | 时间间隔改为 `TimeInterval`，睡眠改为 `Task.sleep(nanoseconds: CompatibleTaskDelay.nanoseconds(for:))` | 数值逐一对齐（0.35 / 0.65 / 1.5 / 0.25 秒），时序行为不变 |
| 23 | `URL.appending(path:)`、`(path:directoryHint:)`、`(queryItems:)` | 16.0 | 48 处：`TiebaEndpoint`（路径 34 + 查询 9）、`TiebaMessageAPI`、`TiebaContentSubmissionAPI`、`AuthSessionTests` | iOS 15 没有这批新拼接 API | `compatibleAppending(...)`：16+ 原样调用；15 用 `appendingPathComponent` / `URLComponents` 拼接 | 请求 URL 逐字符一致（路径均为固定 ASCII 常量；`queryItems` 版按「追加到现有查询」的语义实现） |
| 24 | `NSLocking.withLock` | 16.0 | 28 处：`AvatarView`、`SavedThreadMedia`、`VideoDownloadService`、`SecurityRegressionTests`、`TiebaPostingBootstrapTests` | 标准库版本是 16+ | `withCompatibleLock`（`lock(); defer { unlock() }`，`rethrows`） | 锁语义完全相同；`FileContentDraftPersistence` / `SecureFilePersistence` 内部自定义的 `withLock` 未改动 |
| 25 | `UIViewRepresentable.sizeThatFits(_:uiView:context:)` + `ProposedViewSize` | 16.0 | `ContentBlockView.InlineContentText`、`ImageViewer.ImagePreviewSourceView` | ① 方法签名里带 16+ 类型，15 目标下无法通过可用性检查；② iOS 15 的 SwiftUI 不会调用这个 16+ 钩子，正文文本会退化成 0 高度 | 方法加 `@available(iOS 16.0, *)`；同时给 `InlineContentTextView` 增加 **仅在 < iOS 16 生效** 的 `intrinsicContentSize`，复用原有 `fittingSize(...)` 测量，并在宽度变化/内容变化时 `invalidateIntrinsicContentSize()` | 正文行高、截断、行数上限与 16+ 一致；16+ 完全走原钩子，不受影响 |

### 2.5 无需改动的部分（已在 16.4 时代就正确门控）

- SwiftData：`AppPersistence`、`SwiftDataOrderedCollectionPersistence`、`ContentDraftPersistenceFactory`、`LocalThreadLibrary` 全部在 `@available(iOS 17.0, *)` 内，工程里对 `SwiftData.framework` 是 **weak** 链接；iOS 15 与 16.4 一样走 `SecureFilePersistence` 文件后端。
- iOS 17 / 18 / 26 专属能力：`ContentUnavailableView`（已有 `CompatibleUnavailableView`）、`ToolbarItemPlacement` 的 `toolbar(removing:)`、`Tab`/`TabSection`、`onScrollGeometryChange`、`onScrollPhaseChange`、`sizingRule`、`registerForTraitChanges` 等，原本就包在 `#available` / `@available` 中。
- 网络、Protobuf、图片编解码、语音/视频播放使用的都是 iOS 13–15 级 API。

## 3. iOS 15 上有意保留的行为差异

以下差异来自系统本身没有对应能力，改造选择了「不引入第三方、不改变结构、优雅降级」，逐条列出以便验收时对照：

1. **帖子详情页不隐藏 tab bar**：`.toolbar(.hidden, for: .tabBar)` 是 iOS 16 能力，iOS 15 保持系统默认（tab bar 常显）。这是唯一一处肉眼可见的导航栏差异。
2. **`ViewThatFits` 不做宽度协商**：iOS 15 使用主（横排）布局，仅在无障碍字号时切到紧凑（竖排）布局。极端窄容器（如超大字号 + 分屏）下横排内容可能被压缩，不会溢出或崩溃。
3. **发帖标题单行**：iOS 15 无纵向轴 `TextField`，标题保持单行显示（正文 `TextEditor` 不受影响）。
4. **原图按钮字体**：`fontDesign(.monospaced)` 在 15 不生效，加载中文案的字符宽度不再固定，可能出现轻微横向跳动。
5. **楼中楼 sheet 背景不透明**：`.presentationBackground(.clear)` 需要 16.4，iOS 15 使用系统默认 sheet 背景（改造前 16.0–16.3 也是如此）。
6. **多级 push 的动画**：iOS 15 的栈是逐层 `NavigationLink`，一次性把整条 `path` 设为多级时，两次 push 可能合并为一次动画；逐级返回不受影响。
7. **滚动样式 shim 的可靠性**：`scrollIndicators` / `scrollContentBackground` / `keyboardDismissMode` / `alwaysBounceVertical` 通过视图层级查找底层 `UIScrollView` 施加；找不到时静默保留默认值（只影响装饰，不影响功能）。

## 4. 工程与 CI 改动

| 文件 | 改动 |
|---|---|
| `project.yml` | `deploymentTarget.iOS` 与 `IPHONEOS_DEPLOYMENT_TARGET` 改 `15.0`；`CURRENT_PROJECT_VERSION` 59 → 60（仓库约定：改动 App 的提交必须递增构建号） |
| `TiebaPure.xcodeproj/project.pbxproj` | 同上两项；登记 3 个新增源文件（`CompatibleNavigation/Modifiers/ImagePicker`）与 1 个新增测试文件（`CompatibleNavigationTests`）到对应 target 的 Sources 阶段 |
| `.github/workflows/ci.yml` | 步骤改名 `Verify iOS 15 compatibility linkage`；`MinimumOSVersion` 断言 `16.4` → `15.0`（App 与 OpenIn 扩展各一处）；SwiftData 弱链接断言不变 |
| `README.md` | 支持版本、构建说明、兼容层位置说明 |

## 5. 为什么这样改（取舍说明）

- **不改业务与视图结构**：所有 `[Route]` 路径数组、`*NavigationPathPolicy`、路由枚举、测试都原样保留，改动集中在「API 边界」和「目的地闭包的位置」，因此回归面可控。
- **不引入第三方依赖**：没有用 Introspect / NavigationStackBackport 之类库，滚动与分享的降级用几十行 `UIViewRepresentable` 完成。
- **iOS 16+ 零变化**：每个兼容件的第一分支都是原 API 调用；`ContentBlockView` 新增的 `intrinsicContentSize` 用 `#unavailable(iOS 16.0)` 门控，16+ 完全不执行。
- **可测的纯逻辑抽出来**：栈截断（`CompatibleNavigationPathPolicy.popping`）与延时换算（`CompatibleTaskDelay.nanoseconds`）是不依赖 UI 的纯函数，已加单元测试，避免 iOS 15 分支成为「只能靠肉眼验证」的盲区。

## 6. 验证步骤（macOS + Xcode）

```bash
# 1. 重新生成工程（如需）
xcodegen generate --spec project.yml

# 2. 编译（Debug / Release 各一次，确认无可用性报错与弃用警告）
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# 3. 产物最低版本与弱链接
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' \
  Build/Products/Release-iphoneos/TiebaPure.app/Info.plist          # 期望 15.0
otool -l Build/Products/Release-iphoneos/TiebaPure.app/TiebaPure \
  | awk '/cmd LC_LOAD/{c=$2} /SwiftData.framework/{print c}'          # 期望 LC_LOAD_WEAK_DYLIB

# 4. 单元测试（含新增 CompatibleNavigationTests）
xcodebuild -project TiebaPure.xcodeproj -scheme TiebaPure \
  -destination 'platform=iOS Simulator,id=<iOS 15 机型>' test -only-testing:TiebaPureTests
```

iOS 15 运行时冒烟清单（模拟器或真机）：

1. 首页 → 进吧 → 打开吧 → 打开帖子 → 楼中楼 sheet → 逐级返回（含侧滑返回）。
2. 帖子正文行高、图片九宫格、长文截断与「展开」。
3. 图片查看器：进入/退出转场、双击缩放、保存到相册。
4. 更多菜单：分享（系统分享面板）、浏览器打开。
5. 登录后发回复：选择图片（PHPicker）、进度、发送、草稿保存。
6. iPad 横屏：双栏布局、左侧选中帖子在右栏打开、旋转与分屏折叠。
7. 设置页：阅读设置、本地保存帖子的导入导出（`fileImporter` / `fileExporter`，iOS 14 起可用）。
8. 大字号（辅助功能字号）下各页排版。

## 7. 残余风险

1. **`sizeThatFits` 的可用性标注**：`@available(iOS 16.0, *)` 修饰的是 `UIViewRepresentable` 的尺寸钩子（其 requirement 本身也是 iOS 16+）。若所用工具链要求 witness 与一致性同可用性而报错，替代方案是把该 representable 拆成 16+/15 两个类型（`ContentBlockView` 的测量逻辑集中在 `fittingSize`，拆分成本很低）。
2. **iOS 15 栈的一次性多级 push**：整条路径一次赋值（深链、尺寸类切换桥接）时，动画可能被合并；逐级 push/pop 不受影响。
3. **滚动样式 shim**：依赖视图层级查找 `UIScrollView`，在某些自定义容器里可能找不到（表现是恢复系统默认样式，无功能影响）。

以上 3 点都不影响编译与功能正确性，验收时如发现问题，改动面都在对应的单个兼容件内，可独立修复或回滚。
