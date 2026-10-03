import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Push (Firebase): with no google-services.json yet the app builds and runs
// without pushes (mobile/README.md, "Push").
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// The upload key: made and kept by whoever owns the Google Play account (the
// user's decision), named in android/key.properties; neither is in git.
// Google keeps the key that signs what shoppers install (Play App Signing).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}

// A release without the upload key stops here. It used to be signed with the
// debug key, which Google Play refuses.
gradle.taskGraph.whenReady {
    val release = allTasks.any { it.name == "assembleRelease" || it.name == "bundleRelease" }
    if (release && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "No android/key.properties: a release is signed with the upload key. " +
                "Copy android/key.properties.example and fill it in (mobile/README.md, Builds).",
        )
    }
}

android {
    namespace = "com.saba.saba_marketplace"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The app's ID on Google Play and in Firebase (google-services.json); the
        // user's decision, 2026-10-01. It can never change once published. The
        // namespace above is only the code's package.
        applicationId = "com.sabacompany.sabamarketplace"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
