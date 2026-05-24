# FocusTime

专注时刻是一个 macOS 原生菜单栏倒计时应用。它常驻菜单栏，并在桌面上显示一个轻量的悬浮倒计时卡片，适合番茄钟、专注工作和短时任务管理。

## 下载

请前往 [Releases 页面](https://github.com/siryeah/FocusTime/releases) 下载最新版 DMG 安装包。

如果你不熟悉 GitHub：打开上面的链接后，在最新版本下方找到 `FocusTime-1.0.0-arm64.dmg`，点击即可下载。

## 系统要求

- macOS 26.0 或更高版本
- 当前预构建包为 Apple Silicon / arm64 版本

## 安装

下载 DMG 后，将 `FocusTime.app` 拖入 `Applications` 文件夹即可。

当前内测包未经过 Apple Developer ID 签名和公证。如果 macOS 提示无法验证开发者，可以右键点击应用选择“打开”，或在“系统设置 > 隐私与安全性”中选择“仍要打开”。

如果系统提示应用已损坏，可在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/FocusTime.app
```

## 开发

使用 Xcode 打开：

```bash
open FocusTime.xcodeproj
```

命令行构建 Release：

```bash
xcodebuild -project FocusTime.xcodeproj -scheme FocusTime -configuration Release -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build
```

## 版本

V1.0.0

创意：AI 产品经理四月
