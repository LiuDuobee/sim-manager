import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored) or SIMVAULT_* env vars.
// key.properties keys: storeFile, storePassword, keyAlias, keyPassword.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProperties.getProperty(prop)
val releaseStoreFile = signingValue("storeFile", "SIMVAULT_KEYSTORE")

android {
    namespace = "com.example.sim_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.sim_manager"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("storePassword", "SIMVAULT_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "SIMVAULT_KEY_ALIAS") ?: "simvault"
                keyPassword = signingValue("keyPassword", "SIMVAULT_KEY_PASSWORD")
                    ?: storePassword
            }
        }
    }

    buildTypes {
        release {
            // Without a release key (local dev, forks) fall back to the debug key so
            // `flutter run --release` still works; published APKs must use the release key.
            signingConfig = if (releaseStoreFile != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("SIMVault: no release keystore configured, signing release with the debug key")
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
