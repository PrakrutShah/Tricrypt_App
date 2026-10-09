allprojects {
    repositories {
        google()
        mavenCentral()
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
    val configureNamespace = {
        val extension = project.extensions.findByName("android")
        if (extension is com.android.build.gradle.BaseExtension) {
            if (extension.namespace == null) {
                extension.namespace = "com.example." + project.name.replace("-", "_")
            }
        }
    }
    plugins.withId("com.android.library") { configureNamespace() }
    plugins.withId("com.android.application") { configureNamespace() }
    afterEvaluate { configureNamespace() }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
