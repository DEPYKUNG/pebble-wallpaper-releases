# 开发与验证

最低系统：macOS 13。使用 Xcode Command Line Tools（clang、Swift），Python 3.9 或更新版本；构建同时生成 arm64 和 x86_64。

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
./fetch-sparkle.sh  # 首次下载；已有 work/vendor/Sparkle 时跳过
.venv/bin/python work/package.py --app-only
```

产物为 `build/Pebble Wallpaper.app`。不传 `--app-only` 则同时生成 DMG 到 `outputs/`。构建使用本地 ad hoc 签名；正式 Sparkle 更新签名另外使用钥匙串账号 `app.painted-pebble.wallpaper`，不应提交私钥。

`package.py` 会编译两个架构、验证签名，并启动 `--verify`：检查离线渲染、桌面按钮、背景与颜色、4K 和手机导出，以及 WebKit 故障回调后的状态恢复、取消导航、重试上限与手动恢复。还会验证静态模式停止动画计时、恢复动态时保留旋转开关状态，以及静态模式导出。故障回调由测试注入，不会结束其他应用的 WebKit 进程。

自动更新端到端测试（仅使用独立测试应用标识、临时签名密钥和 localhost feed，不更改正式发布）：

```sh
.venv/bin/python work/update_loopback_test.py --install-mode settings
.venv/bin/python work/update_loopback_test.py --install-mode idle
```

前者验证设置窗口打开时推迟安装，关闭后继续；后者验证直接安装。测试以磁盘 Build 变更和新应用进程启动作为通过条件。运行期间会短暂显示测试壁纸/设置窗口。

菜单栏图标绘制：`work/Pebble.m` 的 `PebbleMenuBarIcon()`；渲染恢复：同文件的 `recoverRenderer:error:`；更新生命周期：`installPendingUpdateIfIdle` 及 Sparkle delegate。
