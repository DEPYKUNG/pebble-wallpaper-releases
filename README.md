# Pebble Wallpaper for macOS

原生 AppKit 菜单栏应用，使用 WebKit 渲染动态壁纸。最低支持 **macOS 13.0**，构建同时包含 Apple Silicon 和 Intel 版本。

[下载最新版](https://github.com/DEPYKUNG/pebble-wallpaper-releases/releases/latest)

## 本地构建

需要 Mac、Xcode Command Line Tools 和 Python 3.9–3.13。在已登录桌面的 macOS 会话运行构建，自检会创建壁纸窗口。

```sh
xcode-select --install
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
./fetch-sparkle.sh
python work/package.py --app-only
```

应用位于 `build/Pebble Wallpaper.app`。去掉 `--app-only` 可生成 DMG。不需要 Sparkle 时可以跳过下载，并运行 `python work/package.py --app-only --update-feed '' --update-key ''`。开发构建使用临时代码签名，无需证书或发布私钥。

- 菜单栏图标由 `work/Pebble.m` 中的 `PebbleMenuBarIcon` 绘制，使用单色鹅卵石轮廓和镂空双眼，由 AppKit 根据菜单栏背景着色。应用图标资源是 `work/app-icon.png`。
- `work/original.html` 和 `work/original.js` 来自 [原作网页](https://painted-pebble.vercel.app/)。本仓库未发现随上游资源提供的再分发许可。Kubai 图标许可见 `work/kubai-settings/LICENSE.txt`。
- 构建后自动运行应用的 `--verify` 自检。可另运行 `python work/update_loopback_test.py`，用临时密钥测试更新。已有环境的测试曾卡在安装器替换应用阶段。

## 发布和自动更新

源码、安装包和 Sparkle 更新均在本仓库维护。已安装的应用从 [签名更新源](https://github.com/DEPYKUNG/pebble-wallpaper-releases/releases/latest/download/appcast.xml) 获取可更新版本。这个固定地址由 GitHub 重定向到 Latest release，应用显示的版本由 appcast 中的版本和构建号决定。

1. 递增 `work/update-release.json` 中的版本号和构建号。构建号必须高于已发布的版本。
2. 在持有原 Sparkle 签名密钥的 macOS 钥匙串所在机器上运行 `python work/package.py`，再运行 `python work/release_update.py "build/Pebble Wallpaper.app" outputs --notes <发行说明文件>`。脚本会核对钥匙串密钥与应用内验证公钥是否匹配，并生成更新 ZIP 和签名 appcast。
3. 在本仓库创建草稿 Release，标签使用 `v<版本号>-<构建号>`。上传同一构建的 DMG、ZIP 和 `appcast.xml`，再将 Release 发布为 Latest。
4. 打开固定更新源地址，确认 appcast 声明本次发布的版本和构建号，且其中的 ZIP 地址可访问。

如需为已发布的 DMG 补发自动更新，用该 DMG 中的应用生成签名产物。先将 ZIP 上传到现有 Release，再替换其 `appcast.xml`。私钥由发布机器的钥匙串保管。
