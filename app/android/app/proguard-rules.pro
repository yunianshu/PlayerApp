# Flutter 嵌入层自带 consumer proguard 规则；这里只补充本工程的保活项。
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.embedding.**

# 定位/SQLite 插件均为平台通道直调，无反射，无需额外 keep。
