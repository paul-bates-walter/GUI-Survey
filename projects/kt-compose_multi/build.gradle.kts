import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    kotlin("jvm") version "2.1.0"
    id("org.jetbrains.compose") version "1.7.3"
    // Kotlin 2.x requires the standalone Compose compiler plugin.
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0"
}

repositories {
    google()
    mavenCentral()
    maven("https://maven.pkg.jetbrains.space/public/p/compose/dev")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(compose.desktop.currentOs)
}

compose.desktop {
    application {
        mainClass = "MainKt"

        nativeDistributions {
            // jpackage bundles a JRE and emits the native installer per host OS.
            targetFormats(TargetFormat.Deb, TargetFormat.Dmg, TargetFormat.Msi)
            packageName = "png-editor-compose"
            packageVersion = "1.0.0"
            description = "Desktop PNG editor (Compose Multiplatform)"
            vendor = "Desktop GUI Survey"

            linux {
                debMaintainer = "desktop-gui-survey@local"
                menuGroup = "Graphics"
            }
            macOS {
                bundleID = "local.desktop-gui-survey.png-editor-compose"
                // Signing/notarization: set signing.sign = true and provide
                // identity + notarization credentials on a macOS build host.
            }
        }
    }
}
