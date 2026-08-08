# Flutter & Audio Service ProGuard / R8 Keep Rules

# Suppress warnings for Play Core deferred components not used in this app
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Keep audio_service native components
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audioservice.AudioService { *; }
-keep class com.ryanheise.audioservice.AudioServiceActivity { *; }
-keep class com.ryanheise.audioservice.MediaButtonReceiver { *; }

# Keep just_audio and audio_session components
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# Keep AndroidX Media and MediaSessionCompat
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }

# Flutter Engine & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep class members used via reflection/JNI
-keepclassmembers class * {
  *** getters();
  *** setters();
  *** invoke(...);
}

# Keep ExoPlayer / Media3 / JustAudio native classes
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
