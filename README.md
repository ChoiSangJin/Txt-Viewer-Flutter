# 고요 · 오프라인 TXT 리더

Android에서 로컬 TXT 소설을 읽는 Flutter 앱입니다. 파일을 시스템 문서 선택기로
불러와 앱 내부 저장소에 복사하며 인터넷 연결이나 전체 저장소 접근 권한을 요구하지 않습니다.
앱 삭제 시 가져온 파일 사본과 읽기 기록도 삭제됩니다. 원본 파일은 수정하지 않습니다.

## 기능

- 서재, 파일 가져오기, 읽던 위치와 읽기 설정 복원
- UTF-8(BOM 포함), UTF-16 LE/BE(BOM 필수), 한글 CP949 텍스트
- 10MiB 이하 TXT 지원, 빈 파일·지원하지 않는 바이너리·손상된 인코딩 오류 안내
- 몰입형 화면, 좌우 영역 탭과 스와이프, 이전/다음 버튼
- **뷰어가 열려 있을 때 볼륨 ↓ 다음 페이지 / 볼륨 ↑ 이전 페이지**
- 중앙 탭 또는 설정 버튼으로 BottomSheet 열기
- 글꼴, 글자 크기, 줄 간격, 문단 여백 변경 및 페이지 재분할
- 시스템/라이트/다크/AMOLED 완전 검정 테마
- 리디바탕, KoPub 바탕, Pretendard를 번들에 포함해 오프라인 전환 지원

## 개발

Flutter **3.35.7** (Dart 3.9), JDK 17, Android SDK가 필요합니다.
프로젝트에는 외부 Dart 런타임 패키지가 없으며 Android 연동은 MethodChannel로 구현합니다.

```sh
flutter --version
flutter doctor -v
flutter pub get
# 첫 의존성 해석 후 생성되는 pubspec.lock을 커밋하세요.
dart format lib test
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
(cd android && ./gradlew app:testDebugUnitTest)
flutter run -d <android-device-id>
```

Flutter가 첫 Android 빌드 시 Gradle wrapper와 로컬 SDK 경로를 준비합니다.
`android/local.properties`와 서명키는 커밋하지 마세요.

### 구조

| 경로 | 역할 |
| --- | --- |
| `lib/main.dart` | 앱 테마와 서재, 글꼴 라이선스 표시 |
| `lib/model.dart` | 서재·읽기 설정과 직렬화된 저장 요청 |
| `lib/reader.dart` | 뷰어, 제스처, 설정, 읽기 위치 추적 |
| `lib/pagination.dart` | 렌더링과 동일한 TextPainter 기반 페이지 분할 |
| `lib/platform.dart` | Android 플랫폼 채널 |
| `android/app/src/main/kotlin/.../MainActivity.kt` | SAF, 앱 전용 파일, 원자적 기록 저장, 볼륨 키 |
| `android/app/src/main/kotlin/.../TextDecoder.kt` | 크기 제한 및 엄격한 한글 인코딩 디코딩 |
| `test/` | 페이지 내용 보존·높이, 서재 복원, 파일 선택·페이지 이동 위젯 테스트 |

페이지는 UTF-16 문자 오프셋으로 기록합니다. 글꼴/크기 또는 화면 방향이 바뀌면 해당
위치를 포함하는 페이지로 복원합니다. 긴 파일의 페이지 분할 중에는 진행 표시를 보여주고
주기적으로 이벤트 루프에 제어를 반환합니다. 한글 CP949는 UTF-8 해석이 실패한 경우에만
시도합니다. BOM 없는 UTF-16과 다른 레거시 인코딩은 지원하지 않습니다.

## ARM64 APK와 배포

```sh
flutter build apk --release --target-platform android-arm64
```

이 옵션이 Flutter 엔진과 네이티브 라이브러리 대상을 제한하므로 별도 `abiFilters`는
필요하지 않습니다. 출력은 `build/app/outputs/flutter-apk/app-release.apk`입니다.
Gradle은 Kotlin DSL(`android/app/build.gradle.kts`)을 사용합니다. Android 15에서 몰입형 UI를
허용하기 위해 targetSdk 35와 `values-v35` 테마의 edge-to-edge opt-out을 지정했습니다.
향후 targetSdk를 올릴 때 Android 16 이상의 시스템 UI 정책을 다시 검증해야 합니다.

릴리스는 **지속적으로 보관할 동일한 서명키**가 필요합니다. 디버그 키로 릴리스하지 않으며,
아래 환경 변수 중 하나라도 없으면 릴리스 서명 단계에서 실패하도록 구성했습니다.
키와 비밀번호를 저장소·로그·채팅에 넣지 마세요. 최초 키는 Android 공식 서명 절차에 따라
생성하고 안전한 위치에 백업해야 합니다. 키를 잃으면 동일 앱의 업데이트를 배포할 수 없습니다.

| 로컬 빌드 환경 변수 | 값의 의미 |
| --- | --- |
| `ANDROID_KEYSTORE_PATH` | 릴리스 keystore의 절대 경로 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 비밀번호 |
| `ANDROID_KEY_ALIAS` | 서명키 별칭 |
| `ANDROID_KEY_PASSWORD` | 키 비밀번호 |

GitHub Actions의 `Android` 워크플로는 PR과 main에서 분석·Flutter 테스트·ARM64 디버그
빌드·Kotlin 디코더 테스트를 실행하고 APK를 artifact로 보관합니다.
GitHub Release 게시에는 저장소 Actions secrets에 아래 항목을 설정한 뒤, **main**에서
워크플로를 수동 실행하고 `release_tag`(예: `v1.0.0`)를 입력합니다.

- `ANDROID_KEYSTORE_BASE64`: 릴리스 keystore를 Base64로 인코딩한 값
- `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

검증 작업이 통과하면 동일 커밋에서 서명된 ARM64 APK를 빌드하여 `goyo-android-arm64.apk`와
`SHA256SUMS`를 GitHub Release에 첨부합니다. 기존 태그의 릴리스는 덮어쓰지 않습니다.
앱 버전을 올릴 때 `pubspec.yaml`의 버전과 Android versionCode도 함께 올려야 합니다.
GitHub Release 배포이며 Google Play 업로드는 포함하지 않습니다.

## 실제 기기 확인

자동 테스트에 더해 배포 전 ARM64 Android 기기에서 다음을 확인해야 합니다.

1. 비행기 모드에서 UTF-8/UTF-16/CP949 파일을 가져오고 세 글꼴을 전환합니다.
2. 상태바·탐색바 숨김, 좌우 탭·느린 스와이프·볼륨 상하 이동을 확인합니다.
3. 글자 크기·줄 간격·문단 여백 변경과 가로/세로 회전 후 누락·겹침이 없는지 확인합니다.
4. 시스템 다크 전환과 AMOLED 검정, 앱 재시작 후 읽던 위치 복원을 확인합니다.
5. 뷰어 종료 후 볼륨 키가 기기의 볼륨을 정상 조절하는지 확인합니다.
6. 파일 선택 취소, 빈 파일, 10MiB 초과 파일, 접근 불가 문서 오류를 확인합니다.

## 글꼴

`assets/fonts/SOURCES.md`에 출처와 파일 해시를 기록했습니다. KoPub 바탕과 Pretendard는
원본 TTF, 리디바탕은 배포본의 원본 OTF를 사용합니다. 두 형식 모두 Flutter 로컬 폰트로
동작하며 네트워크 다운로드는 없습니다. 폰트 라이선스는 번들 및 앱 정보 화면에 포함됩니다.

## 이번 작업의 검증 상태

- Kotlin의 실제 `TextDecoder` 대상 JUnit 테스트: **8개 통과**.
- Dart 파일의 tree-sitter 문법 파싱, 폰트 파일 검증과 Android XML 파싱: 통과.
- Flutter SDK의 Dart 바이너리 다운로드가 환경 네트워크 정책에서 차단되어
  `flutter analyze`, Flutter 테스트, Android APK 빌드는 **미실행**.
- 실제 기기 검증과 서명된 APK 배포는 **미완료**.

문법 파싱은 Flutter 분석/컴파일이나 위젯 테스트를 대신하지 않습니다.
GitHub Actions도 실제 실행 결과를 확인하기 전까지 통과한 것으로 간주하지 않습니다.
