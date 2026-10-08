pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    // Keep the compiler version aligned across AGP and the Flutter plugins.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// nsd_android 2.2.0 still applies the legacy Kotlin plugin. Keep its published
// sources, but use a build script compatible with AGP's built-in Kotlin.
// Remove this adapter once nsd_android ships that migration upstream.
findProject(":nsd_android")?.let { nsdAndroid ->
    val publishedProjectDir = nsdAndroid.projectDir
    val pubspec = publishedProjectDir.parentFile.resolve("pubspec.yaml")
    if (pubspec.readLines().none { it.trim() == "version: 2.2.0" }) return@let

    nsdAndroid.projectDir = file("compat/nsd_android")
    gradle.beforeProject {
        if (path == ":nsd_android") {
            extensions.extraProperties["publishedProjectDir"] = publishedProjectDir
        }
    }
}
