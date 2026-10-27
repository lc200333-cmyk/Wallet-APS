plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val designKeystorePath = System.getenv("DESIGN_ANDROID_KEYSTORE_PATH")
val designKeystorePassword = System.getenv("DESIGN_ANDROID_KEYSTORE_PASSWORD")
val hasDesignSigning = !designKeystorePath.isNullOrBlank() &&
    !designKeystorePassword.isNullOrBlank()
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } &&
    !hasDesignSigning) {
    throw GradleException("Design release requires its persistent signing key; debug fallback is forbidden")
}

android {
    namespace = "com.lc200333cmyk.walletaps"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // Independent experimental installation and private storage.
        applicationId = "com.lc200333cmyk.walletaps.design"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasDesignSigning) {
            create("designRelease") {
                storeFile = file(designKeystorePath!!)
                storeType = "PKCS12"
                storePassword = designKeystorePassword
                keyAlias = "wallet-aps-design"
                keyPassword = designKeystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasDesignSigning) {
                signingConfigs.getByName("designRelease")
            } else {
                null
            }
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

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
