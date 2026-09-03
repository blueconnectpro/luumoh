import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val isReleaseBuild = gradle.startParameter.taskNames.any {
    val task = it.lowercase()
    task.contains("release") || task.contains("bundle")
}
if (isReleaseBuild && !hasReleaseKeystore) {
    throw GradleException(
        "Release signing is not configured. Create android/key.properties from key.properties.example and provide the upload keystore before building a release."
    )
}

android {
    namespace = "com.luumoh.rider"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.luumoh.rider"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

tasks.matching { it.name.matches(Regex("compile.*JavaWithJavac")) }.configureEach {
    doFirst {
        val registrant = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        if (!registrant.exists()) {
            return@doFirst
        }

        val lines = registrant.readLines().toMutableList()
        val pluginLine = lines.indexOfFirst {
            it.contains("dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin")
        }
        if (pluginLine == -1) {
            return@doFirst
        }

        var start = pluginLine
        while (start >= 0 && lines[start].trim() != "try {") {
            start--
        }
        var end = pluginLine
        while (end < lines.size && lines[end].trim() != "}") {
            end++
        }
        if (start >= 0 && end < lines.size) {
            repeat(end - start + 1) {
                lines.removeAt(start)
            }
            registrant.writeText(lines.joinToString(System.lineSeparator()))
        }
    }
}
