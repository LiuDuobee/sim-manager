# SIMVault

全球 SIM/eSIM 收藏、套餐与保号管理工具。本项目坚持本地优先、无需登录、无后端上传，面向集卡党、跨境旅行者和多号码用户。

> Flutter 是跨平台移动端主应用；`android-native/` 是 Android 原生 Compose 路线 C；`simvault/` 是可离线安装的 Web/PWA 版本。

## 主页与下载

- 项目主页：<https://liuduobee.github.io/sim-manager/>
- GitHub Releases：<https://github.com/LiuDuobee/sim-manager/releases>
- Flutter 原生 v3.0.0：<https://github.com/LiuDuobee/sim-manager/releases/tag/v3.0.0>
- Android Compose 原生 v3.1.0：<https://github.com/LiuDuobee/sim-manager/releases/tag/v3.1.0>

## 核心功能

- 管理实体 SIM、原生 eSIM、可编程 eSIM
- 记录运营商、国家、宿主设备、写卡器槽位和卡册位置
- 保号死线、续费提醒、保号打卡和多币种成本
- 本地 JSON 备份与导入，敏感字段支持脱敏导出
- Flutter 深空 Atlas 舞台与 Android Compose HUD 原生版本

## 目录

- `lib/`：Flutter 跨平台主应用
- `android-native/`：Kotlin + Jetpack Compose + MVI Android 原生路线 C
- `simvault/`：React/Vite/Dexie 离线 Web/PWA 实验版本

## 运行

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

当前备份功能通过设置页的 JSON 文本框完成导出/导入，不依赖文件系统插件，后续可将 `BackupService` 接入 `file_picker`、系统分享或云端同步。

## 许可证

GPL-3.0-or-later。欢迎提交 Issue 和 Pull Request。
