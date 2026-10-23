# Pigeon JNI resolves the compiled suspend signatures by their original names.
-keep,includedescriptorclasses class io.flutter.plugins.sharedpreferences.SharedPreferencesApiRegistrar { *; }
-keep,includedescriptorclasses interface io.flutter.plugins.sharedpreferences.SharedPreferencesApi { *; }
-keep,includedescriptorclasses interface kotlin.coroutines.Continuation { *; }

# package:jni also resolves these Kotlin runtime classes and members by name.
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt* { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.Unit { *; }
