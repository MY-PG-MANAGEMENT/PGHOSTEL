plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.pg_manager_owner_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.pg_manager_owner_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // NOTE: no isMinifyEnabled / isShrinkResources / proguardFiles here
            // on purpose. AGP 9 already runs R8 with resource shrinking for
            // release, and the Flutter Gradle plugin contributes the engine
            // keep-rules. Declaring them explicitly only lets hand-written
            // -keep rules hold code that R8 was otherwise dropping: measured on
            // this app, a conservative rule set grew classes.dex from 1.61 MB
            // to 3.86 MB. Leave the defaults alone.
        }
    }

    packaging {
        resources {
            // Build-time metadata that serves no purpose on device. License
            // texts the app must surface stay in Flutter's own NOTICES.Z,
            // which is untouched.
            // Deliberately NOT excluding kotlin/**.kotlin_builtins: it is only
            // ~5 KB and kotlin-reflect would need it at runtime.
            excludes += setOf(
                "META-INF/*.version",
                "META-INF/*.kotlin_module",
                "META-INF/proguard/**",
                "META-INF/com.android.tools/**",
                "DebugProbesKt.bin",
            )
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
