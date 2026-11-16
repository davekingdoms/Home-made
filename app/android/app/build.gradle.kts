import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The keystore and its passwords live outside the repository,
// in private/key.properties at the repository root (ignored by git). storeFile
// is resolved relative to the folder that contains key.properties.
val keyPropertiesFile = rootProject.file("../../private/key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}
val signingKeys = listOf("storePassword", "keyPassword", "keyAlias", "storeFile")

// Properties keeps trailing spaces, which would silently break the passwords.
fun signingValue(key: String): String? = keyProperties.getProperty(key)?.trim()?.ifEmpty { null }
val missingSigningKeys = signingKeys.filter { signingValue(it) == null }
val signingProblem: String? =
    when {
        !keyPropertiesFile.exists() ->
            "Release signing is not configured: expected ${keyPropertiesFile.canonicalPath} " +
                "with ${signingKeys.joinToString()}. Debug builds do not need it."
        missingSigningKeys.isNotEmpty() ->
            "Release signing is not configured: ${keyPropertiesFile.canonicalPath} " +
                "must define ${missingSigningKeys.joinToString()}."
        else -> null
    }

android {
    namespace = "io.github.davekingdoms.homemade"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.davekingdoms.homemade"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (signingProblem == null) {
                storeFile = keyPropertiesFile.parentFile.resolve(signingValue("storeFile")!!)
                storePassword = signingValue("storePassword")
                keyAlias = signingValue("keyAlias")
                keyPassword = signingValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Fail release builds early, with a clear message, when the signing file is missing.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    val problem = signingProblem
    doFirst {
        if (problem != null) {
            throw GradleException(problem)
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
