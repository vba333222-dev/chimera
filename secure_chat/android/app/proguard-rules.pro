# ═══════════════════════════════════════════════════════════════════════════════
# Chimera Secure Chat — ProGuard Rules (Phase 9: App Hardening)
# ═══════════════════════════════════════════════════════════════════════════════
#
# File ini dikonfigurasi untuk Flutter + freeRASP + SQLCipher + cryptography.
# Tujuan:
#   1. Mengobfuskasi class-name sehingga reverse engineering lebih sulit.
#   2. Men-shrink bytecode yang tidak terpakai (reduce APK size).
#   3. Memastikan library kritis tidak ikut dihapus (keep rules).
#
# Cara aktifkan di release build:
#   Di android/app/build.gradle:
#     buildTypes {
#       release {
#         minifyEnabled true
#         shrinkResources true
#         proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
#                       'proguard-rules.pro'
#       }
#     }
# ═══════════════════════════════════════════════════════════════════════════════


# ── Flutter Engine ────────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**


# ── freeRASP (Talsec) ─────────────────────────────────────────────────────────
# freeRASP SDK harus di-keep seluruhnya agar deteksi ancaman tidak rusak
-keep class com.aheaditec.talsec_security.** { *; }
-keepattributes *Annotation*
-dontwarn com.aheaditec.**


# ── SQLCipher ─────────────────────────────────────────────────────────────────
-keep class net.zetetic.database.** { *; }
-keep class net.zetetic.database.sqlcipher.** { *; }
-dontwarn net.zetetic.**


# ── FlutterSecureStorage (Android Keystore) ───────────────────────────────────
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.**


# ── Local Authentication (Biometric) ─────────────────────────────────────────
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**


# ── BouncyCastle (Digunakan oleh SQLCipher dan cryptography) ──────────────────
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# ── OkHttp / WebSocket ────────────────────────────────────────────────────────
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**


# ── Screen Protector ──────────────────────────────────────────────────────────
-keep class com.efficient.screenprotector.** { *; }
-dontwarn com.efficient.screenprotector.**


# ── Kotlin (internal support) ─────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Lazy {
    <fields>;
}


# ── Android Core ─────────────────────────────────────────────────────────────
-keep class androidx.** { *; }
-keep class android.** { *; }
-dontwarn android.**

# Pastikan Parcelable tidak rusak
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}


# ── Serialization (JSON / gson) ───────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses


# ── General Hardening ─────────────────────────────────────────────────────────
# Sembunyikan nama class dari stack trace di production
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable

# Hapus semua logging di release — mencegah information leakage
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
}

# ── Anti-Reverse Engineering ──────────────────────────────────────────────────
# Optimasi agresif untuk mempersulit analisis bytecode
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification
-mergeinterfacesaggressively
