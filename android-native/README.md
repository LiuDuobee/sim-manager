# SIMVault Native Android v3.1.0

路线 C 原生 Android 工程：Kotlin + Jetpack Compose + 单向 MVI 状态流 + 三级能力策略接口。

## 构建

```powershell
.\gradlew.bat assembleRelease
```

输出：

- `app-arm64-v8a-release.apk`：现代 64 位 ARM 手机
- `app-armeabi-v7a-release.apk`：旧款 32 位 ARM 手机
- `app-x86_64-release.apk`：x86_64 模拟器或设备

当前已落地 Standard / Shizuku / APDU 能力策略接口、深空 HUD、Canvas 地球舞台、保号雷达和 Bento 指标面板。硬件提权实现需要用户在设备上分别授予系统、Shizuku 或 OMAPI 权限后接入。
