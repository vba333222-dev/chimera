# ─────────────────────────────────────────────────────────────────────────────
# ProGuard Rules for Chimera — SQLCipher
# REQUIRED: Mencegah code shrinking menghapus kelas SQLCipher pada release build.
# Tanpa aturan ini, aplikasi akan crash saat membuka database terenkripsi.
# ─────────────────────────────────────────────────────────────────────────────

-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# ─────────────────────────────────────────────────────────────────────────────
# ProGuard Rules untuk freeRASP (Talsec RASP SDK)
# Mencegah class native Talsec dihapus saat release build.
# ─────────────────────────────────────────────────────────────────────────────

-keep class com.aheaditec.talsec_security.** { *; }
-keepattributes *Annotation*

