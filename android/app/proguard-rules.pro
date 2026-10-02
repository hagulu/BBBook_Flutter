# google_mlkit_text_recognition은 여러 언어별 TextRecognizerOptions를 optional dependency로 참조한다.
# 이 프로젝트는 한글 인식기(text-recognition-korean)만 포함하므로, 나머지 언어 클래스는
# classpath에 존재하지 않아 R8이 missing class 경고를 낸다. 실제로 사용하지 않으므로 무시한다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**

# 릴리즈에서 WorkManager 초기화 시 "Failed to create an instance of androidx.work.impl.WorkDatabase"가
# 발생하지 않도록, Room이 생성한 WorkDatabase 구현체가 R8에 의해 제거/난독화되지 않게 유지한다.
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
