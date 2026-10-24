# 静锁 QuietLock

一个轻巧的原生 macOS 状态栏工具。点击菜单栏中的 Q 时钟图标，使用滑块快速设置 **1、5、10、15、30 分钟或永不** 自动熄屏。

1.1 版使用原创 Q 时钟图标、冰川青渐变与玻璃面板，时间环随档位流畅变化。拖动越过刻度时会有轻微触觉反馈；方向键和 VoiceOver 操作仍然可用。

1.2 版增加“自动屏保”快捷开关：关闭闲置屏保，重新开启时恢复此前的等待时间（首次无记录时为 20 分钟）。屏保类型和密码要求保持原设置。“永不”同时开启运行期间的原生保持唤醒保护，并每 15 秒以及唤醒、解锁时同步实际设置。

1.3 版重做紧凑界面，固定为 **344 × 420pt**。横向时间卡片、六档滑块、自动屏保开关、错误重试、系统设置、刷新与退出均在首屏内；首次指引和保持唤醒提示复用固定状态区。右上角「ⓘ」可打开完整说明，切换页面不会改变面板高度。AppKit 托管视图和弹出窗口使用相同尺寸，避免首次展开或状态更新时裁切底部内容。

## 使用

1. 打开 `dist/QuietLock.dmg`，将左侧 QuietLock 拖入右侧 Applications 文件夹，然后从“应用程序”打开静锁并推出磁盘映像。应用仅显示在菜单栏，不显示 Dock 图标。更新前请先退出旧版，再拖入并替换。
2. 首次使用，点击“前往设置”，在系统“锁定屏幕”设置中将“屏幕保护程序启动或显示器关闭后，需要密码”设为“立即”。
3. 拖动滑块后松手，或者直接点击刻度。每次启动静锁后的第一次修改需在 macOS 授权弹窗中输入管理员密码，本次运行期间之后的调整不再询问；退出后再打开会重新询问（见下方“免密调整”）。
4. 显示“已设置”表示已读取系统值并验证成功。取消授权则重新显示实际设置。
5. 想避免闲置自动锁屏时，除了选择“永不”，还应关闭面板中的“自动屏保”；屏保有独立的启动定时，即使显示器不自动关闭，屏保仍可能触发密码要求。开启开关会恢复此前的屏保等待时间。

方向键预览档位，Return 或空格应用，Esc 取消预览。也支持 VoiceOver 调整。

**行为说明：**静锁调整的是系统的闲置熄屏时间，统一作用于电池、接电及受支持的 UPS。真正何时需要密码取决于系统锁屏设置。屏幕保护程序、播放视频或其他应用的保持唤醒请求也可能影响实际行为。“永不”关闭自动闲置熄屏定时，并不阻止手动锁屏、合盖、低电量睡眠或系统管理策略。退出静锁不会恢复此前的时间，修改会保留。

选择“永不”时，静锁还会持有 IOKit 的 `PreventUserIdleDisplaySleep` 断言，在运行期间防止屏幕及系统闲置睡眠。退出后释放断言，`pmset` 的熄屏定时和屏保开关仍会保留。系统值被改变时，静锁显示实际值并结束对应的保持唤醒，不会在后台反复覆盖用户或其他应用的新设置。读取失败时保留已有保护，直到能确认新状态。

自动屏保开关修改当前用户、当前 Mac 的 `com.apple.screensaver` 的 `idleTime`，写入后回读确认；不会更改密码策略，也不会退出正在运行的屏保或解锁系统。受组织管理的设置会禁用开关。自动测试及预览使用模拟服务，不会写入真实熄屏或屏保设置。

## 构建

需要 macOS 14+、Xcode 15+ 及其命令行工具，无第三方依赖。

```sh
bash scripts/build.sh
```

产物：`.build/QuietLock.app`（供打包 DMG 使用的中间产物），包含 Apple Silicon 与 Intel 两种架构。构建脚本进行本机临时签名，无需开发者证书。也可直接用 Xcode 打开 `QuietLock.xcodeproj`，选择 QuietLock scheme 运行。

本机版本未做 Developer ID 签名和 Apple 公证。对外分发时应配置自己的 bundle identifier、开发者签名与公证。

### 打包拖动安装 DMG

```sh
bash scripts/package-dmg.sh
```

脚本先构建通用版应用，再生成 `dist/QuietLock.dmg` 及 SHA-256 校验文件。安装窗口包含应用、指向 `/Applications` 的快捷入口和 Retina 品牌背景，无需安装器或管理员权限即可拖动安装（系统文件夹写入权限仍由 macOS 决定）。`dist/` 只包含这两个分发文件。已有最新的 `.build/QuietLock.app` 时，可以添加 `--skip-build` 跳过编译。

DMG 打包额外需要 Python 3.10+，首次运行会联网将固定版本的 `dmgbuild`、`ds-store` 和 `mac-alias` 安装到 `.build/dmg-venv/`。这些依赖仅用于打包，不会包含在应用中。布局直接写入 `.DS_Store`，无需控制 Finder。打包过程不会更改本机电源设置。

重新生成图标：

```sh
xcrun swiftc -parse-as-library QuietLock/BrandMark.swift QuietLock/VisualEffectView.swift Tools/GenerateIcon.swift -o .build/GenerateIcon
.build/GenerateIcon .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o QuietLock/AppIcon.icns
```

## 验证

```sh
bash scripts/test.sh
```

自动测试使用模拟执行器，不修改本机设置，覆盖解析、授权取消、写入失败、部分生效、回读不一致、重复提交与过期读取竞态。

另外包含只读的真实进程验证：读取本机 `pmset` 设置，检查进程输出和退出码。

生成原生视图预览（先运行构建脚本）：

```sh
bash scripts/preview.sh
```

图片保存在 `.build/previews/`。预览工具使用模拟数据，覆盖深浅色、首次指引、自定义时间、时间未统一、永不、授权中、读取失败、屏保读取失败及完整说明，并确认所有状态均为 344 × 420pt。

`design-preview.png` 包含深浅色面板、应用图标和 18pt 状态栏图标预览。状态栏与应用图标共用矢量母版；构建脚本会在设计源文件更新后自动重新生成 ICNS。

人工验收：

- 打开/关闭面板，检查六个刻度、拖动预览、松手吸附和数字过渡。
- 检查深色与浅色，以及系统“减少动态效果”“减少透明度”。
- 首次设置指引可以关闭，并可随时从底部打开系统锁屏设置。
- 在自行授权的一次真实修改后，以 `pmset -g custom` 检查各电源的 `displaysleep`；完成后按需恢复原值。
- 取消授权时应显示原来的实际值，且不报告成功。授权期间不可重复提交。

## 结构

- `QuietLock/`：SwiftUI 面板、AppKit 状态栏容器、无障碍滑块。
- `Sources/QuietLockCore/`：独立 Swift Package，包含解析器、系统服务和状态模型。
- `Tests/QuietLockCoreTests/`：不调用实际授权命令的自动测试。
- `QuietLock/BrandMark.swift`：应用、面板与状态栏共用的原创矢量图标。
- `Tools/GenerateIcon.swift`：渐变应用图标的可重现绘制工具。
- `Tools/GenerateDMGArtwork.swift`、`Tools/dmg-settings.py`：Retina 安装背景和 Finder 拖动安装布局。

系统读取使用 `/usr/bin/pmset -g custom`；修改只允许预设枚举产生的整数进入 `/usr/bin/pmset -a displaysleep <分钟>`。应用不会保存管理员密码，也不会安装特权后台服务。

### 免密调整

每次启动后的第一次修改，通过 AppleScript 的 `with administrator privileges` 弹出一次系统授权，在同一授权内完成修改，并安装 `/etc/sudoers.d/quietlock`：仅允许当前用户免密执行 6 条固定命令（`displaysleep` 为 1、5、10、15、30、0）以及删除该规则本身。规则先经 `visudo -c` 校验，再以 `0440 root:wheel` 安装；校验失败时不安装，不影响本次修改。用户名含空格、引号、逗号等字符时不安装规则，每次仍会询问密码。

本次运行内的后续修改执行 `sudo -n /usr/bin/pmset -a displaysleep <分钟>`（`-n` 不会询问密码）；规则若被移除，则重新弹出授权。“已授权”只记在内存中，因此每次启动都会重新询问。退出静锁（包括注销、关机触发的退出）时以 `sudo -n /bin/rm -f /etc/sudoers.d/quietlock` 删除规则；若因崩溃或强制退出残留，下次启动时会先清理。

注意：静锁运行期间（或崩溃后到下次启动前），本机以该用户身份运行的任何程序都能不输密码把熄屏时间改为这 6 个值之一。也可执行 `sudo rm /etc/sudoers.d/quietlock` 手动撤销。
