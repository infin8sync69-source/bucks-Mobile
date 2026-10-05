# osmdroid loads tile providers and overlays reflectively.
-keep class org.osmdroid.** { *; }
-dontwarn org.osmdroid.**
# Keep line numbers so Play Console crash reports are readable (upload the mapping file with each release).
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# kotlinx.serialization: the library ships its own rules; these keep the generated serializers of the app's @Serializable row classes
# (Supabase rows, push payloads) and their companions, which are only reached through serializer<T>() lookups.
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-dontnote kotlinx.serialization.**
-keep,includedescriptorclasses class com.bucks.app.**$$serializer { *; }
-keepclassmembers class com.bucks.app.** {
    *** Companion;
}
-keepclasseswithmembers class com.bucks.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Ktor (Supabase's HTTP client) refers to JVM-only classes that Android does not have; they are never reached on Android.
-dontwarn org.slf4j.**
-dontwarn java.lang.management.**
-dontwarn io.ktor.util.debug.**
