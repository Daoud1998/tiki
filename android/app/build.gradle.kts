import java.util.Properties

plugins {
 
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    
}
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}




// Fail fast if someone tries to build a RELEASE artifact without proper signing config.
// This prevents accidentally shipping a bundle/APK signed with debug keys.
val isReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
}
val hasKeystoreProps = keystorePropertiesFile.exists()
if (isReleaseTask && !hasKeystoreProps) {
    throw GradleException(
        "Missing android/key.properties for release signing. " +
        "Create key.properties + upload-keystore.jks (upload key) before publishing to Google Play."
    )
}
android {
    // Keep namespace aligned with applicationId to avoid manifest/MainActivity mismatches.
    namespace = "app.tiki.mr"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Must match the Firebase registered package name.
        applicationId = "app.tiki.mr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }


    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
    release {
        // Always sign release builds with the upload key.
        signingConfig = signingConfigs.getByName("release")

        // Optional: enable shrinking via `-PminifyRelease=true` when building.
        val minify = (project.findProperty("minifyRelease") as String?)?.toBoolean() ?: false
        isMinifyEnabled = minify
        isShrinkResources = minify
        proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    }
}
}

flutter {
    source = "../.."
}

dependencies {

    // Firebase (versions managed by BoM)
    implementation(platform("com.google.firebase:firebase-bom:34.8.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")

    // App Check (required for Play Integrity / Debug provider to work reliably on Android)
    implementation("com.google.firebase:firebase-appcheck-playintegrity")
    debugImplementation("com.google.firebase:firebase-appcheck-debug")
}