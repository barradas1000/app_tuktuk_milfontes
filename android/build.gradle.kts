// Ficheiro: android/build.gradle.kts

plugins {
    id("com.android.application") version gradlePluginVersion apply false
    id("org.jetbrains.kotlin.android") version kotlinVersion apply false
}


tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
