# 计算便笺

一个轻量的原生 macOS 计算稿纸。输入算式就会在同一行右侧显示结果，按回车可以把结果带到下一行接着算。

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
open "$HOME/Applications/计算便笺.app"
```

## 实现与许可证

界面用 AppKit 实现。常用四则运算走系统十进制计算，复杂算式按需使用通过 JavaScriptCore 加载的 math.js。

本项目使用 [MIT 许可证](LICENSE)。随源码提供的 math.js 采用 [Apache 2.0 许可证](Vendor/mathjs-LICENSE)，原版权声明见 [NOTICE](Vendor/mathjs-NOTICE)。
