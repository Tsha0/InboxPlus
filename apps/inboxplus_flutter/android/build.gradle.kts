allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val androidToolArtifacts by configurations.creating
dependencies {
    for (host in listOf("linux", "osx", "windows")) {
        androidToolArtifacts("com.android.tools.build:aapt2:9.1.0-14792394:$host")
    }
}

tasks.register("resolveDependencyLocks") {
    doLast {
        allprojects.forEach { project ->
            project.configurations.filter {
                it.isCanBeResolved && !it.name.contains("Test", ignoreCase = true) &&
                    !it.name.endsWith("DependenciesMetadata")
            }.forEach { configuration ->
                configuration.incoming.resolutionResult.allDependencies.forEach {
                    if (it is org.gradle.api.artifacts.result.UnresolvedDependencyResult) throw it.failure
                }
            }
        }
        androidToolArtifacts.resolve()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
