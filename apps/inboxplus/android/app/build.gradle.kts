import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.inboxplus.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.inboxplus.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += setOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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

val connectorRoot = rootProject.file("../../../native/connectors")
val connectorLibraries = layout.buildDirectory.dir("generated/inboxplus/jniLibs")

android.sourceSets.getByName("main").jniLibs.srcDir(connectorLibraries.get().asFile)

dependencies {
    implementation("androidx.core:core:1.18.0")
}

val buildNativeConnectors by tasks.registering(Exec::class) {
    group = "build"
    description = "Build the device-local connectors with Go 1.27.3, Bash, and Android NDK 28.2.13676358."
    workingDir(connectorRoot)
    commandLine(
        "bash", connectorRoot.resolve("build.sh").invariantSeparatorsPath,
        "android", connectorLibraries.get().asFile.invariantSeparatorsPath,
    )
    inputs.files(fileTree(connectorRoot) {
        include("**/*.go", "go.mod", "go.sum", "build.sh")
        exclude("build/**")
    })
    inputs.property("ndkVersion", android.ndkVersion)
    outputs.dir(connectorLibraries)

    doFirst {
        val localProperties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { localProperties.load(it) }
        }
        val sdkPath = localProperties.getProperty("sdk.dir")
            ?: System.getenv("ANDROID_HOME")
            ?: System.getenv("ANDROID_SDK_ROOT")
        val ndkPath = System.getenv("ANDROID_NDK_HOME")
            ?: sdkPath?.let { file(it).resolve("ndk/${android.ndkVersion}").path }
            ?: throw GradleException("Install Android NDK ${android.ndkVersion} and set ANDROID_NDK_HOME.")
        val ndkPropertiesFile = file(ndkPath).resolve("source.properties")
        if (!ndkPropertiesFile.isFile) {
            throw GradleException("Android NDK ${android.ndkVersion} is required to build the local connectors.")
        }
        val ndkProperties = Properties()
        ndkPropertiesFile.inputStream().use { ndkProperties.load(it) }
        if (ndkProperties.getProperty("Pkg.Revision") != android.ndkVersion) {
            throw GradleException("The local connectors require Android NDK ${android.ndkVersion}.")
        }
        environment("ANDROID_NDK_HOME", file(ndkPath).absolutePath)
        environment("ANDROID_API", "24")
    }
}

tasks.named("preBuild") {
    dependsOn(buildNativeConnectors)
}
