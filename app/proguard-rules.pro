# osmdroid loads tile providers and overlays reflectively.
-keep class org.osmdroid.** { *; }
-dontwarn org.osmdroid.**
# Keep line numbers so Play Console crash reports are readable (upload the mapping file with each release).
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
