# Regras de Proguard / R8 para AndroidX Media3, Retrofit, Gson e Room
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class com.digitalsignage.player.data.remote.models.** { *; }
-keep class androidx.media3.** { *; }
