#!/usr/bin/env bash
# 鸿蒙构建脚本：临时切换 pubspec 为鸿蒙版，用 ohos-flutter 3.22 工具构建 hap。
# 用法（Git Bash）:  bash tool/ohos_build.sh [debug|release]
# 前提：已安装 DevEco Studio（含 HarmonyOS SDK），见 docs/harmonyos.md

set -e
cd "$(dirname "$0")/.."

OHOS_FLUTTER="${OHOS_FLUTTER:-/d/soft/ohos-flutter-3.22/bin/flutter.bat}"
MODE="${1:-debug}"

export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# pub 缓存必须与项目同盘（都在 D:），否则 flutter-hvigor-plugin 注入的
# srcPath 无法转成相对路径（path.relative 跨盘符只能回退绝对路径），
# DevEco 6 的 hvigor 会报 "The srcPath is not a relative path"。
export PUB_CACHE="${PUB_CACHE:-D:/AiProject/PlayerApp/.pub-cache-ohos}"

# DevEco 6 的 hvigor 与其自带 API 22 SDK 配套；
# ohos-flutter 自带的 hvigorw 只认 API 12 布局，故 hvigorw.bat 已委托 DevEco。
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-D:\\soft\\DevEco Studio\\sdk}"

cp pubspec.yaml pubspec.yaml.bak
trap 'mv -f pubspec.yaml.bak pubspec.yaml; rm -f pubspec.lock.ohos' EXIT

cp pubspec_ohos.yaml pubspec.yaml
mv pubspec.lock pubspec.lock.bak 2>/dev/null || true

"$OHOS_FLUTTER" pub get
"$OHOS_FLUTTER" build hap --"$MODE"

mv -f pubspec.yaml.bak pubspec.yaml
[ -f pubspec.lock.bak ] && mv -f pubspec.lock.bak pubspec.lock
trap - EXIT

echo "==> 完成：build/ohos/outputs/ 下的 .hap"
