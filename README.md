# 计算便笺

一个轻量的原生 macOS 计算稿纸。输入算式就会在同一行右侧显示结果，按回车可以把结果带到下一行接着算。

## 下载安装

[下载计算便笺 1.3（DMG）](https://github.com/lilei9370-glitch/calc-scratchpad/releases/download/v1.3/CalcScratchpad-1.3-macOS-arm64.dmg) · [查看发布页](https://github.com/lilei9370-glitch/calc-scratchpad/releases/tag/v1.3)

适用于 Apple 芯片的 Mac，需 macOS 14 或更新版本。打开 DMG，把「计算便笺」拖到窗口里的「应用程序」，然后从「应用程序」打开。

发布包使用临时签名，未经过 Apple 公证。首次打开时，如果 macOS 提示无法验证开发者，确认下载来源后，参照 [Apple 官方打开说明](https://support.apple.com/zh-cn/102445) 操作。

## 使用

- 用 ↑ 和 ↓ 在算式之间移动。
- 点击右侧结果可复制数字。光标在算式里且没有选中文字时，⌘C 也会复制当前结果。
- 点时钟打开历史，点 ＋ 或按 ⌘N 新建稿纸。
- 三点菜单里可以复制整张稿纸为图片，也可以对剪贴板里用空格或换行分开的数字求和、求平均。
- 稿纸自动保存在本机，从最后一次编辑起保留 7 天。关掉窗口后应用会退出。

## 从源码构建

当前构建脚本面向 Apple 芯片的 Mac，最低支持 macOS 14。需要安装苹果的 Xcode Command Line Tools。

```sh
xcode-select --install
```

工具装好后，可以在终端下载源码、构建并打开应用。

```sh
git clone https://github.com/lilei9370-glitch/calc-scratchpad.git
cd calc-scratchpad
./build.sh
open "dist/计算便笺.app"
```

若要生成本地下载包，构建后执行下面这条命令。ZIP 包含完整 App、离线运算资源及其许可证。

```sh
ditto -c -k --keepParent "dist/计算便笺.app" "dist/CalcScratchpad-1.3-macOS-arm64.zip"
```

正式分发时，用 `CODE_SIGN_IDENTITY="Developer ID Application: …" ./build.sh` 构建，再按 Apple 的流程公证并装订后重新打包。 [Apple 公证指引](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)

## 实现与许可证

界面用 AppKit 实现。常用四则运算走系统十进制计算，复杂算式按需使用通过 JavaScriptCore 加载的 math.js。

本项目使用 [MIT 许可证](LICENSE)。随源码提供的 math.js 采用 [Apache 2.0 许可证](Vendor/mathjs-LICENSE)，原版权声明见 [NOTICE](Vendor/mathjs-NOTICE)。
