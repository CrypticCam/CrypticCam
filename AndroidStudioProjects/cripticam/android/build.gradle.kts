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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val subproject = this
    // Plugin sisteme dahil olduğu an müdahale eder, timing hatasını önler
    subproject.plugins.whenPluginAdded {
        val plugin = this
        if (plugin::class.java.simpleName.contains("LibraryPlugin")) {
            val android = subproject.extensions.findByName("android")
            if (android is com.android.build.gradle.BaseExtension) {
                if (android.namespace == null) {
                    // Paketin grup ismini (com.github.medcorp...) otomatik namespace yapar
                    android.namespace = subproject.group.toString()
                }
            }
        }
    }
}