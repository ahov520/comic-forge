# Android 本机构建与验证

本轮验证环境（2026-09-06）：Flutter 3.47.2 / Dart 3.13.2、JDK 17、Android SDK 36、Emulator 37.1.11。SDK 位于 `~/Android/Sdk`，AVD 为 `comic_forge_api34`（API 34、Google APIs、x86_64），主机没有 `/dev/kvm`。

## 测试和 APK

从仓库根目录运行：

```bash
export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"

(cd engine && dart test)
(cd app && flutter test)
(cd app && flutter analyze)
(cd app && flutter build apk --release)
```

本轮引擎测试 110 项、Flutter 测试 106 项全部通过，静态分析无问题。界面回归覆盖书架引导、探索分类切换、即时失败与重试、旧请求晚到、源启停，以及窄屏大字号和减少动画设置。

`flutter build apk --release` 已在本机成功，产物为 `app/build/app/outputs/flutter-apk/app-release.apk`，约 61 MB。APK 签名校验通过；包名为 `com.comicforge.comic_forge`，最低 API 24、目标 API 36，包含 arm64-v8a、armeabi-v7a 和 x86_64。

当前项目的 release 构建沿用本机 debug 签名，适合安装验证。构建产物、SDK 路径配置和签名文件不提交仓库。

构建时 `flutter_js` 会提示后续需要迁移 Built-in Kotlin，SDK 工具也有 XML 版本提示；本次均未阻断出包。

## 无 KVM 的模拟器尝试

使用软件加速和无窗口模式，将启动尝试限制为 3 分钟：

```bash
timeout --signal=TERM --kill-after=10s 180s \
  "$ANDROID_SDK_ROOT/emulator/emulator" \
  -avd comic_forge_api34 \
  -accel off -gpu swiftshader_indirect \
  -no-window -no-audio -no-boot-anim -no-snapshot \
  -memory 1536 -cores 2
```

本次 ADB 状态从 `offline` 变成 `device`，但 `sys.boot_completed` 在时限内未返回 `1`；启动进程已按时停止。APK 构建通过，模拟器上的搜索、换源和阅读冒烟尚未完成。

在可完成启动的设备上，可另开终端检查并安装：

```bash
"$ANDROID_SDK_ROOT/platform-tools/adb" devices -l
"$ANDROID_SDK_ROOT/platform-tools/adb" -s emulator-5554 shell getprop sys.boot_completed
# 确认上一条返回 1，再安装并启动。
"$ANDROID_SDK_ROOT/platform-tools/adb" -s emulator-5554 install -r \
  app/build/app/outputs/flutter-apk/app-release.apk
"$ANDROID_SDK_ROOT/platform-tools/adb" -s emulator-5554 shell am start -W \
  -n com.comicforge.comic_forge/.MainActivity
```

验证路径：空书架 → 探索分类与加载/空态 → 搜索收藏 → 详情换源 → 章节阅读与返回续读。设备可用时再补这条路径的操作和截图验证，无需为了软件模拟器长时间阻塞功能开发。
