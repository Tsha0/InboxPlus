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
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

gradle.beforeProject {
    if (name == "media_kit_libs_android_video") {
        val verificationScript = rootProject.projectDir.resolve("../../../Scripts/verify-media-artifacts.py")
        val mediaBuildDirectory = layout.buildDirectory.get().asFile
        val python = System.getenv("PYTHON_BINARY") ?: "python3"
        providers.exec {
            commandLine(
                python, verificationScript.absolutePath, "--platform", "android",
                "--cache-dir", mediaBuildDirectory.resolve("v1.1.7").absolutePath,
            )
        }.result.get().assertNormalExitValue()

        afterEvaluate {
            // The pinned plugin downloads and copies its archives while being configured.
            tasks.named("downloadDependencies") { enabled = false }
            val verifyMedia by tasks.registering(Exec::class) {
                group = "verification"
                commandLine(
                    python, verificationScript.absolutePath, "--platform", "android",
                    "--cache-dir", mediaBuildDirectory.resolve("output").absolutePath,
                )
            }
            tasks.matching { it.name == "preBuild" || it.name == "assemble" }.configureEach {
                dependsOn(verifyMedia)
            }
        }
    }
}
