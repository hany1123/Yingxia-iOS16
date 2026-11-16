# Yingxia16 · 映匣 iOS 16 精简分支

一个能跑在 **iOS 16.0–16.x（含 16.3）** 的 TVBox 订阅播放器，派生自
[jo32/tvbox-silicon](https://github.com/jo32/tvbox-silicon)（Yingxia / 映匣，GPL-3.0）。

## 为什么是精简重写，而不是改一个版本号

上游 iOS 版要求 iOS 17+，实测其官方 IPA：

- `MinimumOSVersion = 17.0`，`LC_BUILD_VERSION minos 17.0 / sdk 27.2`
- **强链接** `/usr/lib/swift/libswiftObservation.dylib` 与 `Symbols.framework`
- 源码 302 个 Swift 文件中 `@Observable` 62 处、`@Bindable` 15 处、
  `.scrollClipDisabled` 53 处，`iOS 16` 可用性分支 0 处

Observation 与 SwiftUI 的观察跟踪是 iOS 17 的系统侧能力，靠 `if #available` 绕不过；
只改 Info.plist 骗得过安装检查，dyld 仍会在启动时失败。上游还依赖嵌入式 JVM、
NodeMobile、FFmpeg、libass 与 iOS 27.2 SDK，公开 CI 无法重建。

因此本分支按 iOS 16 的运行时能力重新实现：数据层用 `ObservableObject` / `@Published`，
UI 只用 iOS 16 及以下 API，编译用 Xcode 16 / iOS 18 SDK，**deployment target 16.0**。

## 保留 / 移除

| 保留 | 移除 |
| --- | --- |
| TVBox JSON 订阅（多订阅合并） | type 3 插件源（JAR / JS / Python） |
| type 0/1/4 JSON 源：分类、分页、搜索、详情 | 嵌入式 JVM、NodeMobile、QuickJS |
| M3U / TXT 直播与分组 | FFmpeg 转封装、libass ASS/SSA 字幕 |
| AVPlayer 原生播放（HLS / MP4） | iOS 17+ SwiftUI 特效、iOS 26/27 特性 |
| 收藏、播放历史、订阅本地保存 | iCloud 同步、PiP 进阶、投屏、下载 |

不内置任何订阅地址，不提供、不托管任何媒体内容。用户自行添加自己有权访问的源。

## 构建

公开仓库的 GitHub Actions（`macos-15-intel` + XcodeGen + 无签名 archive）产出
`Yingxia16.ipa`。本地需 macOS + Xcode 16 + XcodeGen：

```sh
brew install xcodegen
./build_ipa.sh
```

## 安装

产物是**未签名 IPA**（`CODE_SIGNING_ALLOWED=NO`）：

- iOS 16.3 越狱设备：TrollStore / AppSync 直接安装
- 未越狱：用 Sideloadly / AltStore 以个人 Apple ID 重签后安装

Bundle ID `com.yingxia.ios16`，与上游 `com.jo32.yingxia.ios` 不同，可共存。

## 许可

GPL-3.0-only，与上游一致。派生来源与第三方声明见 [LICENSE](LICENSE) 及上游仓库
`Docs/THIRD_PARTY_NOTICES.md`。本仓库即为该修改版对应的源码。
