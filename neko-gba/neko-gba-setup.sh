#!/usr/bin/env bash
# =============================================================================
# neko-gba-setup v0.2
# Crea la estructura completa del proyecto en ~/neko-gba
#
# Uso:
#   bash neko-gba-setup-v0.2.sh
#
# Qué hace:
#   1. Crea todos los directorios
#   2. Crea archivos de código vacíos (solo package/mod declaration)
#   3. Escribe contenido final en archivos de configuración
#
# Correcciones respecto a v0.1:
#   - READ/WRITE_EXTERNAL_STORAGE eliminados del Manifest (no funcionan en
#     API 29+ para getExternalFilesDir, que no necesita permiso)
#   - android:icon eliminado del Manifest hasta que exista el drawable
#   - externalNativeBuild vacío eliminado de build.gradle.kts
#   - Compose Compiler 1.5.10 → 1.5.11 (compatible con Kotlin 1.9.23)
#   - navigation-compose añadido a dependencies{} (estaba en catalog pero no usado)
#   - kotlinx-serialization añadido (necesario para JSON en repositories)
#   - compose-bom 2024.04.01 → 2024.05.00 (Material3 1.2.1 estable)
#   - Cargo.toml: rustboyadvance-ng anclado con comentario de reproducibilidad
#   - Archivos de código: vacíos en lugar de TODO() que no compila
# =============================================================================
set -e

ROOT="$HOME/neko-gba"

if [ -d "$ROOT" ]; then
  echo "⚠  '$ROOT' ya existe."
  read -r -p "¿Sobreescribir? (s/N): " confirm
  if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
    echo "Cancelado."
    exit 0
  fi
fi

echo "Creando proyecto neko-gba en $ROOT ..."
echo ""

# =============================================================================
# 1. DIRECTORIOS
# =============================================================================
echo "── Directorios..."

mkdir -p "$ROOT/.cargo"

# Rust core
mkdir -p "$ROOT/core/src/gba"
mkdir -p "$ROOT/core/src/audio"
mkdir -p "$ROOT/core/src/video"
mkdir -p "$ROOT/core/src/link_cable"
mkdir -p "$ROOT/core/src/save"
mkdir -p "$ROOT/core/src/cheats"
mkdir -p "$ROOT/core/src/fastforward"
mkdir -p "$ROOT/core/src/jni"

# Android app — Java packages
JAVA="$ROOT/app/src/main/java/dev/neko/nekogba"
mkdir -p "$JAVA/core/bridge"
mkdir -p "$JAVA/core/link"
mkdir -p "$JAVA/core/audio"
mkdir -p "$JAVA/core/video"
mkdir -p "$JAVA/data/model"
mkdir -p "$JAVA/data/external"
mkdir -p "$JAVA/data/repository"
mkdir -p "$JAVA/domain/usecase"
mkdir -p "$JAVA/ui/screens"
mkdir -p "$JAVA/ui/components"
mkdir -p "$JAVA/ui/viewmodel"
mkdir -p "$JAVA/ui/theme"

# Android app — resources y assets
mkdir -p "$ROOT/app/src/main/res/drawable"
mkdir -p "$ROOT/app/src/main/res/layout"
mkdir -p "$ROOT/app/src/main/res/values"
mkdir -p "$ROOT/app/src/main/res/raw"
mkdir -p "$ROOT/app/src/main/assets/filters"
mkdir -p "$ROOT/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$ROOT/app/src/main/jniLibs/armeabi-v7a"

# Tests
mkdir -p "$ROOT/app/src/test/java/dev/neko/nekogba"
mkdir -p "$ROOT/app/src/androidTest/java/dev/neko/nekogba"

# Gradle
mkdir -p "$ROOT/gradle/wrapper"

# Docs y filtros
mkdir -p "$ROOT/docs/external-formats"
mkdir -p "$ROOT/filters/crt"
mkdir -p "$ROOT/filters/clean"

echo "   ✓ $(find "$ROOT" -type d | wc -l) directorios creados"
echo ""

# =============================================================================
# 2. ARCHIVOS DE CÓDIGO VACÍOS
#    Solo la declaración mínima: package en Kotlin, mod/use en Rust.
#    Sin lógica, sin TODO(), sin imports inventados.
# =============================================================================
echo "── Archivos de código (vacíos)..."

# ── Rust ──────────────────────────────────────────────────────────────────────

cat > "$ROOT/core/src/lib.rs" << 'RUST_EOF'
pub mod gba;
pub mod audio;
pub mod video;
pub mod link_cable;
pub mod save;
pub mod cheats;
pub mod fastforward;
pub mod jni;
RUST_EOF

cat > "$ROOT/core/src/gba/mod.rs" << 'RUST_EOF'
// GBA emulator wrapper — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/audio/mod.rs" << 'RUST_EOF'
// Audio: volumen general y salida PCM — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/video/mod.rs" << 'RUST_EOF'
// Video: framebuffer y pipeline de filtros — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/link_cable/mod.rs" << 'RUST_EOF'
pub mod shared_memory;
pub mod wifi_local;
RUST_EOF

cat > "$ROOT/core/src/link_cable/shared_memory.rs" << 'RUST_EOF'
// Link Cable mismo dispositivo: memoria compartida — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/link_cable/wifi_local.rs" << 'RUST_EOF'
// Link Cable dos dispositivos: WiFi local sin internet — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/save/mod.rs" << 'RUST_EOF'
// Save states formato mGBA, 10 slots por juego — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/cheats/mod.rs" << 'RUST_EOF'
// Motor de cheats GameShark y CodeBreaker — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/fastforward/mod.rs" << 'RUST_EOF'
// Fast-forward: toggle/hold, prioridad hold > toggle, umbral warning — implementar aquí
RUST_EOF

cat > "$ROOT/core/src/jni/mod.rs" << 'RUST_EOF'
// Funciones JNI exportadas a Kotlin — implementar aquí
RUST_EOF

# ── Kotlin: core ──────────────────────────────────────────────────────────────

cat > "$JAVA/core/bridge/EmulatorBridge.kt" << 'KT_EOF'
package dev.neko.nekogba.core.bridge
KT_EOF

cat > "$JAVA/core/link/LinkCableManager.kt" << 'KT_EOF'
package dev.neko.nekogba.core.link
KT_EOF

cat > "$JAVA/core/link/SharedMemoryLink.kt" << 'KT_EOF'
package dev.neko.nekogba.core.link
KT_EOF

cat > "$JAVA/core/link/WifiLocalLink.kt" << 'KT_EOF'
package dev.neko.nekogba.core.link
KT_EOF

cat > "$JAVA/core/audio/AudioEngine.kt" << 'KT_EOF'
package dev.neko.nekogba.core.audio
KT_EOF

cat > "$JAVA/core/video/VideoRenderer.kt" << 'KT_EOF'
package dev.neko.nekogba.core.video
KT_EOF

# ── Kotlin: data/model ────────────────────────────────────────────────────────

cat > "$JAVA/data/model/Game.kt" << 'KT_EOF'
package dev.neko.nekogba.data.model
KT_EOF

cat > "$JAVA/data/model/SaveSlot.kt" << 'KT_EOF'
package dev.neko.nekogba.data.model
KT_EOF

cat > "$JAVA/data/model/GameStats.kt" << 'KT_EOF'
package dev.neko.nekogba.data.model
KT_EOF

cat > "$JAVA/data/model/CheatEntry.kt" << 'KT_EOF'
package dev.neko.nekogba.data.model
KT_EOF

cat > "$JAVA/data/model/ControlLayout.kt" << 'KT_EOF'
package dev.neko.nekogba.data.model
KT_EOF

cat > "$JAVA/data/model/FastForwardConfig.kt" << 'KT_EOF'
package dev.neko.nekogba.data.model
KT_EOF

# ── Kotlin: data/external y repository ───────────────────────────────────────

cat > "$JAVA/data/external/ExternalFileManager.kt" << 'KT_EOF'
package dev.neko.nekogba.data.external
KT_EOF

cat > "$JAVA/data/repository/SaveRepository.kt" << 'KT_EOF'
package dev.neko.nekogba.data.repository
KT_EOF

cat > "$JAVA/data/repository/StatsRepository.kt" << 'KT_EOF'
package dev.neko.nekogba.data.repository
KT_EOF

cat > "$JAVA/data/repository/CheatRepository.kt" << 'KT_EOF'
package dev.neko.nekogba.data.repository
KT_EOF

cat > "$JAVA/data/repository/LayoutRepository.kt" << 'KT_EOF'
package dev.neko.nekogba.data.repository
KT_EOF

cat > "$JAVA/data/repository/GameLibraryRepository.kt" << 'KT_EOF'
package dev.neko.nekogba.data.repository
KT_EOF

# ── Kotlin: domain/usecase ────────────────────────────────────────────────────

cat > "$JAVA/domain/usecase/LoadGameUseCase.kt" << 'KT_EOF'
package dev.neko.nekogba.domain.usecase
KT_EOF

cat > "$JAVA/domain/usecase/SaveStateUseCase.kt" << 'KT_EOF'
package dev.neko.nekogba.domain.usecase
KT_EOF

cat > "$JAVA/domain/usecase/ApplyCheatUseCase.kt" << 'KT_EOF'
package dev.neko.nekogba.domain.usecase
KT_EOF

cat > "$JAVA/domain/usecase/GetLibraryUseCase.kt" << 'KT_EOF'
package dev.neko.nekogba.domain.usecase
KT_EOF

cat > "$JAVA/domain/usecase/UpdateStatsUseCase.kt" << 'KT_EOF'
package dev.neko.nekogba.domain.usecase
KT_EOF

# ── Kotlin: ui/viewmodel ──────────────────────────────────────────────────────

cat > "$JAVA/ui/viewmodel/EmulatorViewModel.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.viewmodel
KT_EOF

cat > "$JAVA/ui/viewmodel/LibraryViewModel.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.viewmodel
KT_EOF

cat > "$JAVA/ui/viewmodel/ControlsViewModel.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.viewmodel
KT_EOF

cat > "$JAVA/ui/viewmodel/CheatViewModel.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.viewmodel
KT_EOF

# ── Kotlin: ui/screens ────────────────────────────────────────────────────────

cat > "$JAVA/ui/screens/MainActivity.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

cat > "$JAVA/ui/screens/AppNavHost.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

cat > "$JAVA/ui/screens/LibraryScreen.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

cat > "$JAVA/ui/screens/EmulatorScreen.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

cat > "$JAVA/ui/screens/ControlsEditorScreen.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

cat > "$JAVA/ui/screens/CheatsScreen.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

cat > "$JAVA/ui/screens/SettingsScreen.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

cat > "$JAVA/ui/screens/LinkCableScreen.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.screens
KT_EOF

# ── Kotlin: ui/components ─────────────────────────────────────────────────────

cat > "$JAVA/ui/components/TouchButton.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.components
KT_EOF

cat > "$JAVA/ui/components/FastForwardOverlay.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.components
KT_EOF

cat > "$JAVA/ui/components/SaveSlotPicker.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.components
KT_EOF

cat > "$JAVA/ui/components/GameThumbnail.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.components
KT_EOF

cat > "$JAVA/ui/components/FilterSelector.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.components
KT_EOF

cat > "$JAVA/ui/components/AudioControls.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.components
KT_EOF

# ── Kotlin: ui/theme ──────────────────────────────────────────────────────────

cat > "$JAVA/ui/theme/Theme.kt" << 'KT_EOF'
package dev.neko.nekogba.ui.theme
KT_EOF

echo "   ✓ Archivos de código creados (vacíos)"
echo ""

# =============================================================================
# 3. ARCHIVOS DE CONFIGURACIÓN (contenido final, no cambiará)
# =============================================================================
echo "── Configuración final..."

# ── .cargo/config.toml ───────────────────────────────────────────────────────
cat > "$ROOT/.cargo/config.toml" << 'EOF'
[target.aarch64-linux-android]
linker = "aarch64-linux-android21-clang"

[target.armv7-linux-androideabi]
linker = "armv7a-linux-androideabi21-clang"
EOF

# ── Cargo.toml (workspace) ────────────────────────────────────────────────────
cat > "$ROOT/Cargo.toml" << 'EOF'
[workspace]
members = ["core"]
resolver = "2"
EOF

# ── core/Cargo.toml ───────────────────────────────────────────────────────────
# NOTA: rustboyadvance-ng no tiene releases en crates.io, solo git.
# Se usa git = ... sin rev fijo porque el repo no tiene tags estables.
# Cuando empieces a integrar, fija el rev al commit que uses:
#   rev = "abc1234"
# para que los builds sean reproducibles.
cat > "$ROOT/core/Cargo.toml" << 'EOF'
[package]
name = "neko-gba-core"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]
name = "neko_gba_core"

[dependencies]
# IMPORTANTE: fijar rev al commit que uses antes de distribuir
# rev = "abc1234"
rustboyadvance-ng = { git = "https://github.com/michelhe/rustboyadvance-ng" }
jni               = "0.21"
log               = "0.4"
android_logger    = "0.13"
serde             = { version = "1", features = ["derive"] }
serde_json        = "1"
EOF

# ── settings.gradle.kts ───────────────────────────────────────────────────────
cat > "$ROOT/settings.gradle.kts" << 'EOF'
rootProject.name = "neko-gba"
include(":app")
EOF

# ── build.gradle.kts (raíz) ───────────────────────────────────────────────────
cat > "$ROOT/build.gradle.kts" << 'EOF'
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android)      apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
EOF

# ── gradle/libs.versions.toml ─────────────────────────────────────────────────
# Correcciones:
#   - compose-bom: 2024.04.01 → 2024.05.00 (Material3 1.2.1 estable)
#   - kotlinx-serialization añadido (necesario para JSON en repositories)
#   - navigation-compose añadido al catálogo y a plugins
cat > "$ROOT/gradle/libs.versions.toml" << 'EOF'
[versions]
agp                    = "8.4.0"
kotlin                 = "1.9.23"
compose-bom            = "2024.05.00"
compose-compiler       = "1.5.11"
core-ktx               = "1.13.0"
lifecycle              = "2.7.0"
activity-compose       = "1.9.0"
navigation-compose     = "2.7.7"
coil                   = "2.6.0"
coroutines             = "1.8.0"
serialization          = "1.6.3"

[libraries]
androidx-core-ktx                    = { group = "androidx.core",              name = "core-ktx",                     version.ref = "core-ktx" }
androidx-lifecycle-runtime-ktx       = { group = "androidx.lifecycle",          name = "lifecycle-runtime-ktx",        version.ref = "lifecycle" }
androidx-lifecycle-viewmodel-compose = { group = "androidx.lifecycle",          name = "lifecycle-viewmodel-compose",  version.ref = "lifecycle" }
androidx-activity-compose            = { group = "androidx.activity",           name = "activity-compose",             version.ref = "activity-compose" }
androidx-compose-bom                 = { group = "androidx.compose",            name = "compose-bom",                  version.ref = "compose-bom" }
androidx-ui                          = { group = "androidx.compose.ui",         name = "ui" }
androidx-ui-graphics                 = { group = "androidx.compose.ui",         name = "ui-graphics" }
androidx-material3                   = { group = "androidx.compose.material3",  name = "material3" }
androidx-navigation-compose          = { group = "androidx.navigation",         name = "navigation-compose",           version.ref = "navigation-compose" }
coil-compose                         = { group = "io.coil-kt",                  name = "coil-compose",                 version.ref = "coil" }
kotlinx-coroutines-android           = { group = "org.jetbrains.kotlinx",       name = "kotlinx-coroutines-android",   version.ref = "coroutines" }
kotlinx-serialization-json           = { group = "org.jetbrains.kotlinx",       name = "kotlinx-serialization-json",   version.ref = "serialization" }

[plugins]
android-application  = { id = "com.android.application",            version.ref = "agp" }
kotlin-android       = { id = "org.jetbrains.kotlin.android",        version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
EOF

# ── app/build.gradle.kts ──────────────────────────────────────────────────────
# Correcciones:
#   - externalNativeBuild vacío eliminado
#   - composeOptions: 1.5.10 → 1.5.11
#   - navigation-compose añadido a dependencies{}
#   - kotlinx-serialization añadido
cat > "$ROOT/app/build.gradle.kts" << 'EOF'
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace  = "dev.neko.nekogba"
    compileSdk = 34

    defaultConfig {
        applicationId = "dev.neko.nekogba"
        minSdk        = 26
        targetSdk     = 34
        versionCode   = 1
        versionName   = "1.0"

        // cargo-ndk construye los .so y los deposita en jniLibs/
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        // Debe coincidir con la versión de Kotlin 1.9.23
        kotlinCompilerExtensionVersion = "1.5.11"
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.coil.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
}
EOF

# ── proguard-rules.pro (vacío pero requerido por build.gradle.kts) ────────────
touch "$ROOT/app/proguard-rules.pro"

# ── gradle.properties ─────────────────────────────────────────────────────────
cat > "$ROOT/gradle.properties" << 'EOF'
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
org.gradle.jvmargs=-Xmx2048m
EOF

# ── gradle/wrapper/gradle-wrapper.properties ──────────────────────────────────
cat > "$ROOT/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.6-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# ── AndroidManifest.xml ───────────────────────────────────────────────────────
# Correcciones:
#   - READ/WRITE_EXTERNAL_STORAGE eliminados: getExternalFilesDir() no los necesita
#   - android:icon eliminado: no existe el drawable todavía
cat > "$ROOT/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="dev.neko.nekogba">

    <!--
        ACCESS_WIFI_STATE + INTERNET: requeridos para Link Cable por WiFi local.
        CHANGE_WIFI_MULTICAST_STATE: para autodiscovery mDNS entre dispositivos.
        No se necesitan permisos de storage: usamos getExternalFilesDir()
        que es accesible sin permiso desde API 19.
    -->
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:label="neko-gba"
        android:theme="@style/Theme.NekoGba"
        android:supportsRtl="true">

        <activity
            android:name=".ui.screens.MainActivity"
            android:exported="true"
            android:screenOrientation="landscape"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

    </application>
</manifest>
EOF

# ── res/values/strings.xml ────────────────────────────────────────────────────
cat > "$ROOT/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">neko-gba</string>
    <string name="ff_warning">⚠ Velocidad alta puede romper el juego</string>
    <string name="no_roms">No se encontraron ROMs .gba</string>
    <string name="save_state">Guardar estado</string>
    <string name="load_state">Cargar estado</string>
    <string name="slot">Slot</string>
    <string name="fast_forward">Fast Forward</string>
    <string name="link_cable">Cable Link</string>
    <string name="cheats">Cheats</string>
    <string name="settings">Ajustes</string>
</resources>
EOF

# ── res/values/colors.xml ─────────────────────────────────────────────────────
cat > "$ROOT/app/src/main/res/values/colors.xml" << 'EOF'
<resources>
    <color name="amoled_black">#FF000000</color>
    <color name="surface_dark">#FF0D0D0D</color>
    <color name="accent_purple">#FF9B59B6</color>
    <color name="text_primary">#FFFFFFFF</color>
    <color name="text_secondary">#FF9E9E9E</color>
    <color name="warning_yellow">#FFFFC107</color>
</resources>
EOF

# ── res/values/themes.xml ─────────────────────────────────────────────────────
cat > "$ROOT/app/src/main/res/values/themes.xml" << 'EOF'
<resources>
    <style name="Theme.NekoGba" parent="Theme.Material3.Dark.NoActionBar">
        <item name="android:windowBackground">@color/amoled_black</item>
        <item name="android:statusBarColor">@color/amoled_black</item>
        <item name="android:navigationBarColor">@color/amoled_black</item>
    </style>
</resources>
EOF

# ── filters/ ──────────────────────────────────────────────────────────────────
cat > "$ROOT/filters/README.md" << 'EOF'
# Filter Scripts

Añade nuevos filtros aquí sin tocar el código fuente.

## Formato
Cada filtro es un subdirectorio que contiene:
- `<nombre>.filter.json` — metadata y parámetros
- La clase de implementación se registra en runtime via VideoRenderer.loadFilterScript()

El pipeline es modular: crea la carpeta, implementa la clase, regístrala.
EOF

cat > "$ROOT/filters/clean/clean.filter.json" << 'EOF'
{
  "name": "Clean",
  "version": "1.0",
  "description": "Sin filtro — píxeles directos sin procesado",
  "entry": "CleanFilterScript",
  "params": {}
}
EOF

cat > "$ROOT/filters/crt/crt.filter.json" << 'EOF'
{
  "name": "CRT",
  "version": "1.0",
  "description": "Simula el efecto de scanlines de un monitor CRT",
  "entry": "CrtFilterScript",
  "params": {
    "scanline_opacity": 0.4,
    "barrel_distortion": 0.02
  }
}
EOF

# ── docs/external-formats/ ────────────────────────────────────────────────────
cat > "$ROOT/docs/external-formats/save-state.md" << 'EOF'
# Save State Format

**Estándar:** mGBA-compatible exclusivamente.
**Slots:** 10 por juego (slot_0.ss0 … slot_9.ss9).
**Ruta:** `<getExternalFilesDir()>/neko-gba/saves/<gameId>/`

Cada slot es un archivo independiente.
Se puede guardar estado en cualquier momento del juego.
EOF

cat > "$ROOT/docs/external-formats/stats.md" << 'EOF'
# Game Stats Format

**Archivo:** `<getExternalFilesDir()>/neko-gba/stats/<gameId>/stats.json`

```json
{
  "gameId": "sha1-of-rom",
  "playTimeMs": 123456,
  "lastPlayed": 1713888000000,
  "launchCount": 42
}
```
EOF

cat > "$ROOT/docs/external-formats/cheats.md" << 'EOF'
# Cheats Format

**Archivo:** `<getExternalFilesDir()>/neko-gba/cheats/<gameId>/cheats.json`

Tipos soportados: `GAMESHARK`, `CODEBREAKER`

```json
[
  { "label": "HP infinito", "code": "DEADBEEF 00FF", "type": "GAMESHARK", "enabled": true }
]
```
EOF

cat > "$ROOT/docs/external-formats/layout.md" << 'EOF'
# Control Layout Format

**Archivo:** `<getExternalFilesDir()>/neko-gba/layouts/layout.json`

Portable entre dispositivos. Posiciones normalizadas (0.0–1.0) para escalar a cualquier pantalla.

```json
{
  "version": 1,
  "buttons": [
    { "id": "A",      "xNorm": 0.88, "yNorm": 0.60, "sizeDp": 52,  "alphaPct": 80 },
    { "id": "B",      "xNorm": 0.80, "yNorm": 0.75, "sizeDp": 52,  "alphaPct": 80 },
    { "id": "START",  "xNorm": 0.55, "yNorm": 0.88, "sizeDp": 40,  "alphaPct": 70 },
    { "id": "SELECT", "xNorm": 0.45, "yNorm": 0.88, "sizeDp": 40,  "alphaPct": 70 },
    { "id": "D_PAD",  "xNorm": 0.12, "yNorm": 0.65, "sizeDp": 110, "alphaPct": 75 },
    { "id": "L",      "xNorm": 0.05, "yNorm": 0.10, "sizeDp": 60,  "alphaPct": 70 },
    { "id": "R",      "xNorm": 0.95, "yNorm": 0.10, "sizeDp": 60,  "alphaPct": 70 }
  ]
}
```
EOF

# ── .gitignore ────────────────────────────────────────────────────────────────
cat > "$ROOT/.gitignore" << 'EOF'
# Android build
/app/build/
/build/

# Rust build
/core/target/

# Gradle
.gradle/
local.properties
*.iml

# IDE
.idea/

# APK
*.apk
*.aab

# NDK libs compiladas (se generan con cargo-ndk, no se commitean)
/app/src/main/jniLibs/

# El gradle-wrapper.jar SÍ debe commitearse si usas ./gradlew
# Generarlo con: gradle wrapper --gradle-version 8.6
EOF

# ── README.md ─────────────────────────────────────────────────────────────────
cat > "$ROOT/README.md" << 'EOF'
# neko-gba

Emulador GBA personal. Núcleo en Rust + UI Android en Kotlin (Jetpack Compose).
Basado en RustBoyAdvance-NG.

## Features
- Save states formato mGBA, 10 slots por juego, archivos externos independientes
- Fast-forward: valor numérico libre, modos toggle y hold (hold siempre tiene prioridad)
- Controles táctiles: reposicionables, transparencia ajustable, layout portable
- Link Cable: mismo dispositivo (memoria compartida) + dos dispositivos (WiFi local)
- Filtros: CRT y limpio — añadir nuevos como scripts sin recompilar
- Cheats: GameShark y CodeBreaker
- Biblioteca con miniatura visual
- AMOLED dark mode exclusivo

## Estructura de archivos externos en el dispositivo
```
<getExternalFilesDir()>/neko-gba/
  saves/<gameId>/slot_0.ss0 … slot_9.ss9
  stats/<gameId>/stats.json
  cheats/<gameId>/cheats.json
  layouts/layout.json
```

## Setup inicial

### Prerrequisitos
- Android Studio (con NDK y SDK 34)
- Rust + cargo: https://rustup.rs
- cargo-ndk: `cargo install cargo-ndk`
- Targets Rust para Android:
  ```
  rustup target add aarch64-linux-android armv7-linux-androideabi
  ```

### Gradle wrapper
El archivo `gradle/wrapper/gradle-wrapper.jar` no está en el repo.
Generarlo con:
```
gradle wrapper --gradle-version 8.6
```
O descargar Android Studio que lo incluye automáticamente.

### Build de la librería Rust
```
cd core
cargo ndk -t arm64-v8a -t armeabi-v7a -o ../app/src/main/jniLibs build --release
```

### Build del APK
```
./gradlew assembleRelease
```

## Notas
- `targetSdk = 34` es deliberado: API 35 introduce cambios de edge-to-edge
  que romperían el layout del emulador.
- `rustboyadvance-ng` se toma de git. Fijar el `rev` al commit que uses
  antes de distribuir el APK para builds reproducibles.
EOF

echo "   ✓ Configuración final escrita"
echo ""

# =============================================================================
# RESUMEN
# =============================================================================
DIRS=$(find "$ROOT" -type d | wc -l)
FILES=$(find "$ROOT" -type f | wc -l)

echo "============================================="
echo "  ✓ neko-gba creado en $ROOT"
echo "  $DIRS directorios"
echo "  $FILES archivos"
echo "============================================="
echo ""
echo "Próximos pasos:"
echo "  1. Instalar prerrequisitos (ver README.md)"
echo "  2. Generar gradle wrapper: gradle wrapper --gradle-version 8.6"
echo "  3. Abrir la carpeta en Android Studio"
echo "  4. Empezar implementando: core/src/gba/mod.rs"
