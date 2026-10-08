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
    // AGP's built-in Kotlin uses this compiler version.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// Use built-in Kotlin for nsd_android 2.2.0 until its build script is updated.
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
