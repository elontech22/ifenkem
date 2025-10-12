# Keep Google Play Core classes used by Flutter's PlayStoreDeferredComponentManager
-keep class com.google.android.play.** { *; }
-keep interface com.google.android.play.** { *; }
-dontwarn com.google.android.play.**

# (Optional) Keep Flutter deferred components glue (defensive)
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }
