# ZClock

macOS 菜单栏时钟，显示指定时区的时间，支持自定义显示格式。

应用图标采用双时区光环方案，源图位于 `Resources/AppIcon.png`。

点击菜单栏时间，选择「设置…」。在设置窗口输入日期格式（例如 `yyyy-MM-dd HH:mm:ss` 或 `yyyy-MM`），查看预览后点击「应用到菜单栏」。搜索城市或地区并点击即可切换时区。格式与时区都会自动保存。

「登录时启动」使用 macOS 登录项。设置窗口会显示系统返回的实际状态；如需批准，可直接打开系统登录项设置，返回后点击「重新检查」。

## 构建与安装

需要 macOS 13 或更新版本，以及 Xcode 命令行工具。

```sh
zsh scripts/build.sh
ditto dist/ZClock.app ~/Applications/ZClock.app
open ~/Applications/ZClock.app
```

应用不会显示在 Dock；从菜单栏的「退出 ZClock」退出。
