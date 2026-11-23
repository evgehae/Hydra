plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "app.hydra"
    compileSdk = 35

    defaultConfig {
        applicationId = "warp.claude.app"
        minSdk = 26
        targetSdk = 35
        // versionCode — монотонный из CI (нужен Android для установки поверх).
        // versionName — «человеческий» WARP CLAUDE 3.x
        val vc = (project.findProperty("versionCode") as String?)?.toIntOrNull() ?: 3
        versionCode = vc
        versionName = "3.$vc"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }

    val storeFilePath = System.getenv("HYDRA_KEYSTORE_FILE")
        ?: (project.findProperty("HYDRA_KEYSTORE_FILE") as String?)
    val storePassword = System.getenv("HYDRA_KEYSTORE_PASSWORD")
        ?: (project.findProperty("HYDRA_KEYSTORE_PASSWORD") as String?)
    val keyAlias = System.getenv("HYDRA_KEY_ALIAS")
        ?: (project.findProperty("HYDRA_KEY_ALIAS") as String?)
        ?: "hydra"
    val keyPassword = System.getenv("HYDRA_KEY_PASSWORD")
        ?: (project.findProperty("HYDRA_KEY_PASSWORD") as String?)
        ?: storePassword

    signingConfigs {
        if (!storeFilePath.isNullOrBlank() && !storePassword.isNullOrBlank()) {
            create("release") {
                storeFile = file(storeFilePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword ?: storePassword
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            val hasRelease = signingConfigs.findByName("release") != null
            if (hasRelease) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation(files("libs/hydra.aar"))
}
