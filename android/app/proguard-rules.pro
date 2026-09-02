# google_mlkit_text_recognition은 여러 언어별 TextRecognizerOptions를 optional dependency로 참조한다.
# 이 프로젝트는 한글 인식기(text-recognition-korean)만 포함하므로, 나머지 언어 클래스는
# classpath에 존재하지 않아 R8이 missing class 경고를 낸다. 실제로 사용하지 않으므로 무시한다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
