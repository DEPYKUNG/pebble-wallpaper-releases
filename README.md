# Pebble Wallpaper for macOS

原生 AppKit 菜单栏应用，使用 WebKit 渲染动态壁纸。最低支持 **macOS 13.0**，构建同时包含 Apple Silicon 和 Intel 版本。

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

- 菜单栏图标在 `work/Pebble.m` 的 `applicationDidFinishLaunching:` 中，通过 `imageWithSystemSymbolName:@"circle.hexagongrid.fill"` 加载 SF Symbol。应用图标资源是 `work/app-icon.png`。
- `work/original.html` 和 `work/original.js` 来自 [原作网页](https://painted-pebble.vercel.app/)。本仓库未发现随上游资源提供的再分发许可。Kubai 图标许可见 `work/kubai-settings/LICENSE.txt`。
- 构建后自动运行应用的 `--verify` 自检。可另运行 `python work/update_loopback_test.py`，用临时密钥测试更新。已有环境的测试曾卡在安装器替换应用阶段。
- `work/update-release.json` 仅含公开更新源、验证公钥和版本号。正式安装包与签名更新位于 [发布仓库](https://github.com/DEPYKUNG/pebble-wallpaper-releases)。
