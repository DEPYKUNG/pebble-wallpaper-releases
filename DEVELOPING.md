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

菜单栏图标绘制：`work/PebbleMenuIcon.m` 的 `PebbleMenuBarIcon()`；渲染恢复：`work/PebbleAppRendering.m` 的 `recoverRenderer:error:`；更新生命周期：`work/PebbleAppUpdates.m` 的 `installPendingUpdateIfIdle` 及 Sparkle delegate。


P1 回归检查（原生数据与壁纸策略测试不修改系统桌面）：

```sh
python3 work/test_state.py
python3 work/test_wallpaper_policy.py
```

石头记录格式为 `schemaVersion: 1`，兼容无版本的旧记录，新增 yaw/pitch 姿态。首次迁移或过滤坏数据前，在本地偏好 `PebbleDataBackupBeforeSchema1` 保留原始收藏和历史。收藏读取当前渲染快照，并按形状、材质、颜色和脸孔去重。

原生深色背景固定保存在 `~/Library/Application Support/Pebble Wallpaper/Desktop Backgrounds/`，不再依赖应用包路径。恢复逻辑记录每块屏幕的原图与接管 URL；用户外部修改优先，断开的屏幕和恢复失败的原图记录保留待处理。静态 PNG 的手机导出从已保存的 4K 图片排版，不依赖隐藏动态画面。

`--verify` 还会检查导出菜单的屏幕标识、指定屏幕重新抛/上一颗、静态 PNG 的各手机尺寸、失败指令的反馈以及普通页面重载后的最新设置与石头。当前本机仅单屏，多屏选择与断连边界由独立模拟标识测试覆盖，尚未进行实体双屏断接验收。完整渲染检查包含高清图片处理，构建超时上限为 60 秒。


设置背景由 `work/PebbleSettingsSurface.m` 管理。使用 macOS 26 SDK 构建时，通过可用性判断和弱链接，在 macOS 26 或更新系统使用 `NSGlassEffectView` Regular；macOS 13–15 或旧 SDK 构建使用 `NSVisualEffectView` 毛玻璃。单一材质承托整个设置窗口，alpha 保持 1，设置卡片以 90% 不透明度保证可读性。「减少透明度」开启时，材质内容下的实色衬底显示，并动态响应系统设置变化。

仅设置预览（不接管系统壁纸或启动更新检查）：`"build/Pebble Wallpaper.app/Contents/MacOS/Pebble" --preview-settings`。可追加 `--preview-light`、`--preview-dark`、`--preview-frosted` 或 `--preview-solid` 检查不同样式；这些覆盖只在预览/截图模式生效。`--shoot` 的视图缓存截图用于布局检查，玻璃折射和背景模糊仍需实屏验证。


关于页更新日志：维护 `work/changelog.json`，每次发布新增版本、整数 Build、ISO 日期和简短摘要，并保留既有记录。`package.py` 会验证当前版本/Build 有对应日志，按整数 Build 倒序打包不晚于当前构建的最近三条到 `Resources/changelog.json`；不会在启动时联网抓取日志。「查看全部」沿用 GitHub Releases 历史页。隔离更新测试构建允许没有对应正式版日志。

运行 `python3 work/test_changelog.py` 验证版本排序、三条上限、当前版本匹配及异常记录拒绝。布局可用 `--shoot <输出路径> 3 --preview-frosted --preview-light` 或 `--preview-dark` 检查；`--preview-settings --preview-about` 可直接打开关于页实屏预览。应用本身再次限制展示三条，长摘要随窗口宽度换行。


应用入口与生命周期保留在 `work/Pebble.m`。`PebbleAppMenu.m` 管理菜单与选项，`PebbleAppRendering.m` 管理 WebKit/显示器/暂停，`PebbleAppWallpaper.m` 管理收藏、导出与系统壁纸，`PebbleAppSettings.m` 管理设置布局，`PebbleAppPass.m` 管理石头证，`PebbleAppUpdates.m` 管理更新，`PebbleAppVerification.m` 管理现有回归检查。共享属性与类型化方法契约集中在内部头 `PebbleAppInternal.h`；这些 category 共用一个应用实例，未改变状态所有权。后续新增功能应放在所属模块，不继续堆进入口文件。


P2 渲染构建：`work/renderer_build.py` 负责离线组装；自有 JavaScript、样式和页面片段位于 `work/renderer/bridge.js`、`wallpaper.css`、`body.html`，颜色表位于 `colors.json`。`patches.json` 是按名称标识的上游适配补丁，每个锚点必须且只能出现一次；`upstream.json` 固定 `original.js` / `original.html` 的 SHA256，并声明原生调用所需的 JS API。任何文件指纹、补丁、材质字典或 API 不匹配都会拒绝构建，不会继续打包不完整的渲染页面。

更新上游时，应先保留并检查差异，逐条适配命名补丁，核查材质字典和 `bridge.js` 使用的上游接口（如 `Mg`）；审查完成后再更新指纹。不能只刷新 SHA256 绕过校验。运行 `python3 work/test_renderer_build.py`、既有状态/壁纸策略/日志测试和完整 `package.py --app-only` 回归后才能发布。当前仍使用固定版本的上游压缩代码，适配层将这个依赖集中在一个有明确校验的边界内，不承诺任意上游版本可直接替换。

本次重构前后生成的 `wallpaper.html`、`PebbleTextures.h`、`PebbleColors.h` 已逐字节比对一致。兼容性测试另覆盖上游漂移、锚点缺失/重复、重复补丁名、材质字典部分匹配、原生 API 丢失、不安全脚本及模板缺失。
