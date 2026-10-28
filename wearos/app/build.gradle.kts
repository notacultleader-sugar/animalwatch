plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "com.pokewatch"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.pokewatch.tamapoke"
        minSdk = 30 // Wear OS 3+ (Galaxy Watch4 and newer)
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // personal sideload build: sign with the debug key so it installs over adb
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(project(":game"))
}
