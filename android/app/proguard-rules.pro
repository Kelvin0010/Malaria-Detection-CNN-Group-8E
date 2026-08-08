# Keep Flutter JNI and embedding classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep all native methods in any class from being shrunk or renamed
-keepclassmembers class * {
    native <methods>;
}

# Explicitly keep FlutterJNI and all of its members/inner classes
-keep class io.flutter.embedding.engine.FlutterJNI {
    *;
}
-keep class io.flutter.embedding.engine.FlutterJNI$* {
    *;
}



# Keep TensorFlow Lite (needed for ML model inference)
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.internal.firebase_auth.** { *; }

# Ignore warnings about optional Play Core classes used by Flutter PlayStore Split install
-dontwarn com.google.android.play.core.**

