# SIM 卡管理 Flutter App

一个中文 Flutter 跨平台 SIM/eSIM 资料管理工具，使用 `shared_preferences` 本地持久化。

仓库根目录的 Flutter 工程是正式移动端应用；`simvault/` 是此前生成的 Web/Capacitor 实验原型，不作为 Flutter APK 的实现来源。

`android-native/` 是路线 C 的 Kotlin + Jetpack Compose 原生 Android 工程，当前版本为 v3.1.0，使用 MVI 和 Standard / Shizuku / APDU 能力策略接口。

## 运行

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

当前备份功能通过设置页的 JSON 文本框完成导出/导入，不依赖文件系统插件，后续可将 `BackupService` 接入 `file_picker`、系统分享或云端同步。
