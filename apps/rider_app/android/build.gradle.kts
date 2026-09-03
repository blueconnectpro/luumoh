import com.android.build.api.dsl.LibraryExtension

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
    plugins.withId("com.android.library") {
        if (name == "mapbox_maps_flutter") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }

        extensions.configure<LibraryExtension>("android") {
            if (namespace.isNullOrBlank()) {
                val manifestFile = file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val packageName = Regex("""package\s*=\s*["']([^"']+)["']""")
                        .find(manifestFile.readText())
                        ?.groupValues
                        ?.get(1)
                    if (!packageName.isNullOrBlank()) {
                        namespace = packageName
                    }
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
