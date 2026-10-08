// Build configuration for the published nsd_android 2.2.0 sources.
// Its upstream script still applies KGP and configures the removed kotlinOptions
// DSL. Keep namespace, SDK levels and JVM targets aligned with that script.
// https://github.com/sebastianhaberey/nsd/tree/main/nsd_android

plugins {
    id("com.android.library")
}

val publishedProjectDir: File by extra

configure<com.android.build.api.dsl.LibraryExtension> {
    namespace = "com.haberey.flutter.nsd_android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
    }

    sourceSets.getByName("main") {
        manifest.srcFile(publishedProjectDir.resolve("src/main/AndroidManifest.xml"))
        kotlin.directories.add(publishedProjectDir.resolve("src/main/kotlin").absolutePath)
    }
}
