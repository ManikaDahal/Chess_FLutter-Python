# ============================================================
# CRITICAL: Keep ALL JNI native methods across all classes.
# R8/ProGuard must NOT rename methods called from native C/C++ code.
# flutter_screen_recording uses JNI - this rule is essential.
# ============================================================
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# ============================================================
# Flutter Screen Recording - Keep ALL classes, inner classes, and methods.
# Without this, R8 strips the MediaProjection activity callback in release.
# ============================================================
-keep class com.isvisoft.flutter_screen_recording.** { *; }
-keepclassmembers class com.isvisoft.flutter_screen_recording.** { *; }
-dontwarn com.isvisoft.flutter_screen_recording.**

# ============================================================
# The ForegroundService used by flutter_screen_recording for MediaProjection.
# This is a separate package that MUST be kept intact.
# ============================================================
-keep class com.foregroundservice.** { *; }
-keepclassmembers class com.foregroundservice.** { *; }
-dontwarn com.foregroundservice.**

# ============================================================
# Flutter Foreground Task (Sticky Notification)
# ============================================================
-keep class com.pravera.flutter_foreground_task.** { *; }
-keepclassmembers class com.pravera.flutter_foreground_task.** { *; }
-dontwarn com.pravera.flutter_foreground_task.**

# ============================================================
# Keep ALL Activity and Service subclasses intact.
# R8 likes to optimize away onActivityResult, which breaks MediaProjection.
# ============================================================
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keepclassmembers class * extends android.app.Activity {
    public void onActivityResult(int, int, android.content.Intent);
}

# ============================================================
# Flutter WebRTC
# ============================================================
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn com.cloudwebrtc.webrtc.**
-dontwarn org.webrtc.**

# ============================================================
# Permission Handler
# ============================================================
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# ============================================================
# Firebase & Google Play Services
# ============================================================
-keep class io.flutter.plugins.firebase.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ============================================================
# Flutter Core Plugin Registration
# ============================================================
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class io.flutter.plugins.** { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }

# ============================================================
# AndroidX
# ============================================================
-keep class androidx.lifecycle.** { *; }
-keep class androidx.core.app.** { *; }
-dontwarn androidx.**

# ============================================================
# Suppress all other warnings (safe for Flutter apps)
# ============================================================
-dontwarn **
