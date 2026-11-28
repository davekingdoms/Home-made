import java.net.URI
import java.util.Base64
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

// Host of the App Links of the invites, from PAGES_BASE_URL. The domain stays
// out of the repository: Flutter passes the dart-defines to Gradle as
// -Pdart-defines, base64 KEY=VALUE pairs joined by commas, also those of
// --dart-define-from-file.
val dartDefines: Map<String, String> =
    (findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotEmpty() }
        ?.mapNotNull { encoded ->
            val pair = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            val separator = pair.indexOf('=')
            if (separator > 0) pair.substring(0, separator) to pair.substring(separator + 1) else null
        }
        ?.toMap()
        ?: emptyMap()
val pagesBaseUrl: String? = dartDefines["PAGES_BASE_URL"]?.trim()?.ifEmpty { null }
val pagesHost: String? =
    pagesBaseUrl
        ?.let { runCatching { URI(it) }.getOrNull() }
        ?.takeIf { it.scheme == "https" && !it.host.isNullOrEmpty() && (it.path.isNullOrEmpty() || it.path == "/") }
        ?.takeIf { it.query == null && it.fragment == null && it.userInfo == null && it.port == -1 }
        ?.host
val pagesProblem: String? =
    when {
        pagesBaseUrl == null ->
            "PAGES_BASE_URL is missing: build with --dart-define-from-file=<env file> " +
                "(see app/env.example.json). The App Links of the invites need its host."
        pagesHost == null ->
            "PAGES_BASE_URL must be an https address with a host only, no path, port or query: " +
                "the App Links of the invites need its host."
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
        // Host of the invite links, in the intent filter of the manifest. A
        // build without it stops before this matters (pagesProblem).
        manifestPlaceholders["invitesHost"] = pagesHost ?: "invalid.invalid"
    }

    // Two flavors of the same app, which fit side by side on a phone: dev
    // (package .dev, test builds) and prod (the real app). Neither the
    // namespace nor the Kotlin package follows the application ID. At startup
    // the app checks that the flavor agrees with APP_ENV (AppConfig).
    // The names also live in AppFlavor.appName, for the app switcher.
    buildFeatures {
        // resValue below: off by default since AGP 9.
        resValues = true
    }
    flavorDimensions += "env"
    // Each flavor takes the invite links of its own path, as InviteLinks in
    // the app builds them, so the two apps never take each other's links.
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Home-made dev")
            manifestPlaceholders["invitesPath"] = "/dev/invite"
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Home-made")
            manifestPlaceholders["invitesPath"] = "/invite"
        }
    }

    // One signing key for both flavors: the upload key in release builds,
    // the debug key in debug builds.
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

// Fail release builds early, with a clear message, when the signing file is
// missing: preDevReleaseBuild and preProdReleaseBuild.
tasks.matching { it.name.startsWith("pre") && it.name.endsWith("ReleaseBuild") }.configureEach {
    val problem = signingProblem
    doFirst {
        if (problem != null) {
            throw GradleException(problem)
        }
    }
}

// Fail every build early, with a clear message, without a usable
// PAGES_BASE_URL: preBuild runs before the manifest is merged.
tasks.matching { it.name == "preBuild" }.configureEach {
    val problem = pagesProblem
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
