# Fuji San X-M5 / X-T5 실험적 수정판

이 파일은 원본 v0.3.0-alpha.1을 수정한 **소스 코드**입니다. 실행 파일(EXE/APK/APP)이 아닙니다. 아래 절차로 빌드해야 실행할 수 있습니다. 원본 최신 EXE를 다운로드하면 이 수정 내용은 포함되지 않습니다.

## 구현한 내용과 확인 범위

- X-M5 모델 인식, 모델 선택 화면, C1–C4 슬롯 표시·조회·백업·전송·복원 경로.
- 원본 X100VI 모델의 C1–C7 경로 유지.
- X-T5 모델 인식, C1–C7 조회·백업·전송·복원 경로와 읽기 전용 호환성 진단. 실제 X-T5 연결은 미검증이며 속성 설명 오류에 다른 기종의 예외 처리를 적용하지 않음.
- Fuji X Weekly 원문의 작례 사진을 보며 고르는 카탈로그. 내장 항목 중 해당 원문을 가진 175개 항목을 기본 사진 화면에 표시.
- X-M5에서 C5–C7을 요청하면 USB 명령을 보내기 전에 중단.
- 전송 전 설정값의 범위 확인. X100VI 1.32와 X-M5 1.20에 한해 속성 설명 요청의 `0x2002` 오류를 앱의 설정 범위 검사로 대체. 다른 펌웨어나 다른 응답 오류에는 적용하지 않음.
- 원본의 백업 저장 및 전송 후 읽기 검증 유지. 실패 시 자동 복구를 보장하지 않음.
- 카메라 설정이나 슬롯 선택을 변경하지 않는 호환성 진단 추가.
- 수정판 데이터는 별도 `fuji-san-xm5` 폴더에 저장. 원본으로 자동 업데이트하지 않음.

**X-M5 1.20의 USB 선택값 1~4 변경·읽기·원래 선택값 복원은 실기에서 확인했습니다.** 서로 다른 두 종류의 레시피가 읽혔고, 원래 선택값에서 읽은 레시피 필드도 보존됐습니다. 이후 색농도 단일 설정 저장도 사용자가 확인했습니다. 실제 C1~C4 전체 대응, 모든 레시피 설정 쓰기와 레시피 백업 복원은 아직 실기 미검증입니다. X-M5 1.20의 전송은 기존 앱의 설정 범위·확인한 2바이트 읽기 형태를 바탕으로 구현한 실험적 지원이며, 모든 값의 쓰기 허용 여부가 입증된 것은 아닙니다. 필요한 속성·자료형이 없거나 알려지지 않은 백업 값이 읽히면 중단합니다.

확인 완료: 실제 수정한 Dart 프로토콜·모델 코드를 모의 USB 전송에 연결하여 오프라인 검사 20개 통과. C슬롯 범위, 스캔·쓰기·복원, 다른 슬롯 보존, 범위 밖 설정과 다른 펌웨어 차단, 읽기 전용 진단, 슬롯 진단의 실패·복원 경로와 기존 X100VI 동작을 검사했습니다. X-T5의 7개 슬롯과 다른 기종의 예외 처리 차단도 모의 검사했습니다. GitHub Actions에서 전체 Flutter 분석·테스트 71개와 PHP 검사가 통과했습니다 (플랫폼 전용 테스트 1개 제외). 작례 사진 탐색·갤러리·오프라인 대체 경로와 모바일 화면 검사가 포함됩니다. 실제 X-M5 1.20의 USB 선택값 1~4 변경·읽기·원래 선택값 복원과 원래 선택값에서 읽은 레시피 필드 보존을 확인했고, 색농도 단일 설정 저장은 사용자가 확인했습니다. 실제 C번호 전체 대응·전체 레시피 전송·복원과 X-T5 실기는 미검증입니다.

최초 수정판의 완료된 빌드: https://github.com/jfh5z77ptt-png/fuji-san-xm5/actions/runs/37961523354

슬롯 진단 기능을 포함한 수정판의 완료된 빌드: https://github.com/jfh5z77ptt-png/fuji-san-xm5/actions/runs/38019260968

X-M5 1.20 조회·실험적 전송 수정판의 완료된 빌드 (Windows·macOS·Android·iOS): https://github.com/jfh5z77ptt-png/fuji-san-xm5/actions/runs/38021981562

작례 사진 카탈로그와 X-T5 실험적 모드를 포함한 수정판의 완료된 빌드 (Windows·macOS·Android·iOS): https://github.com/jfh5z77ptt-png/fuji-san-xm5/actions/runs/38064993686

## 사진으로 레시피 고르기

1. 앱의 `내장 레시피`를 엽니다. 기본 화면은 `작례 사진`과 `Fuji X Weekly만` 필터입니다.
2. 사진 카드에서 색감을 보고 원하는 레시피를 누릅니다.
3. 좌우 화살표나 스와이프로 원문의 작례를 최대 12장 비교합니다. 돋보기로 크게 볼 수 있습니다.
4. 설정값을 확인하고 `라이브러리에 추가`를 누릅니다. 카메라 연결 없이도 사진을 보고 추가할 수 있습니다.
5. `설정 목록`을 누르면 다른 제작자를 포함한 전체 540개 항목도 확인할 수 있습니다.

사진은 Fuji X Weekly 원문에 공개된 작례이며 출처와 원문 링크를 표시합니다. 앱에 사진을 묶어 배포하거나 디스크에 저장하지 않고 인터넷으로 불러옵니다. 연결이 끊기거나 원문 형식이 바뀌면 사진을 표시하지 못할 수 있지만 설정 조회·라이브러리 추가·원문 열기는 계속 사용할 수 있습니다. 모든 원문 사진이나 X-M5로 촬영한 결과를 보장하는 기능은 아닙니다.

## X-T5 연결

카메라 모델에서 `X-T5 (실험적)`를 선택하면 C1–C7을 표시합니다. 실제 연결된 기종을 읽으면 모델과 슬롯 수를 자동으로 맞춥니다. USB 연결 모드는 `USB RAW CONV./BACKUP RESTORE`를 사용합니다.

실제 X-T5 USB 응답은 아직 받지 않았습니다. 먼저 `도구 → 카메라 호환성 진단`을 실행하고 펌웨어·속성 응답을 확인하세요. 이 진단은 설정값이나 슬롯 선택값을 쓰지 않습니다. X-T5에서 속성 설명을 읽지 못하면 슬롯 선택이나 레시피 쓰기를 중단합니다. X100VI 1.32 / X-M5 1.20의 `0x2002` 예외를 X-T5에 확대하지 않습니다. 정상 연결되면 레시피 백업 후 테스트 슬롯 하나부터 확인하세요.

공식 X-T5 커스텀 설정 문서: https://fujifilm-dsc.com/en-int/manual/x-t5/menu_shooting/image_quality_setting/

## 실행 파일 만드는 방법 A: GitHub Actions

로컬에 Flutter나 Visual Studio를 설치하지 않고 GitHub의 빌드 컴퓨터에서 실행 파일을 만드는 방법입니다. GitHub 계정과 본인 저장소가 필요합니다.

1. 원본 https://github.com/reikop/fuji-san 을 본인 계정에 Fork 합니다.
2. 이 압축 파일을 풀고, 아래 파일을 본인 Fork의 같은 경로에 업로드하여 교체/추가합니다. `Add file → Upload files`를 이용하거나 git으로 올릴 수 있습니다. 파일들은 **저장소 최상위 기준의 경로**를 유지해야 합니다. `.github` 폴더도 포함하세요.

   ```text
   .github/workflows/ci.yml
   README.md
   XM5_GUIDE.md
   BUILD_WINDOWS.ps1
   BUILD_MACOS.sh
   lib/camera/camera.dart
   lib/camera/model.dart
   lib/diagnostics.dart
   lib/main.dart
   lib/storage.dart
   lib/builtin_recipes.dart
   lib/recipe_photos.dart
   lib/recipe_references.dart
   test/builtin_recipes_test.dart
   test/recipe_references_test.dart
   test/xm5_test.dart
   test/xm5_ui_test.dart
   test/slot_navigation_test.dart
   tool/offline_protocol_check.py
   ```

3. 저장소의 `Actions` 탭에서 Fork의 Actions 실행을 활성화합니다.
4. `X-M5 experimental builds → Run workflow`를 선택합니다. 이 워크플로는 Flutter 코드 분석과 전체 테스트에 성공한 뒤 Windows·macOS·Android·iOS를 빌드합니다. 하나의 플랫폼이 실패해도 다른 플랫폼의 결과는 따로 확인할 수 있습니다.
5. 원하는 플랫폼의 빌드가 성공하면 실행 결과 하단 `Artifacts`에서 다운로드합니다.
   - Windows: `fuji-san-xm5-windows-experimental`
   - macOS: `fuji-san-xm5-macos-experimental`
6. Windows는 다운로드한 Artifact ZIP을 풀고 내부 `fuji-san-windows.zip`도 풉니다. **폴더 전체를 유지한 채 `fuji_san.exe`를 실행**합니다.
7. macOS는 Artifact 안의 `fuji-san-macos.tar.gz`를 풀어 앱을 실행합니다. 미서명 개발 빌드이므로 macOS 실행 허용 또는 로컬 서명이 필요할 수 있습니다. iOS 결과는 바로 설치 가능한 IPA가 아닙니다.

소스 압축 파일에는 GitHub 계정 정보나 실행 파일이 들어 있지 않습니다. 이미 완료된 위 빌드의 Artifacts를 받으면 직접 소스를 업로드하거나 Flutter를 설치할 필요가 없습니다.

## 실행 파일 만드는 방법 B: 본인 컴퓨터

### Windows

Flutter SDK 3.47.6, Git, Visual Studio의 `Desktop development with C++` 구성요소가 필요합니다. `flutter doctor`에서 Windows 빌드 항목을 확인합니다.

소스 폴더에서 PowerShell을 열어:

```powershell
.\BUILD_WINDOWS.ps1
```

직접 명령을 실행하려면:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release --dart-define=FUJI_DEFAULT_MODEL=X-M5
```

결과: `build\windows\x64\runner\Release\fuji_san.exe`. `Release` 폴더의 DLL과 `data` 폴더도 함께 필요합니다.

### macOS

Flutter SDK 3.47.6, Xcode와 필요한 macOS 빌드 도구를 설치한 후 소스 폴더에서:

```bash
bash BUILD_MACOS.sh
```

결과: `build/macos/Build/Products/Release/fuji_san.app`.

## X-M5 연결과 첫 확인

1. 필름 시뮬레이션 다이얼을 **C**에 둡니다. FS1~FS3는 이 앱의 C1~C4 레시피 슬롯과 다릅니다.
2. 사용할 C1~C4를 **사진 촬영용**으로 설정합니다. 메뉴 `이미지 품질 설정 → 사용자 모드 설정`에서 확인할 수 있습니다.
3. `네트워크/USB 설정 → USB 전원 공급/통신 설정`을 `AUTO` 또는 `전원 공급 OFF/통신 ON`으로 설정합니다.
4. 같은 메뉴의 연결 모드를 **USB RAW CONV./BACKUP RESTORE**로 설정합니다.
5. X RAW STUDIO, TETHER APP, 사진 가져오기 등 다른 카메라 연결 프로그램을 종료합니다. 데이터 전송 가능한 USB 케이블로 연결하고 카메라를 켭니다.
6. **처음에는 앱의 `도구 → 카메라 호환성 진단`부터 실행**합니다. 일반 카메라 연결에 실패한 상태에서도 실행할 수 있습니다. 카메라 한 대만 연결하세요.
7. 표시된 JSON을 복사하여 보관합니다. 카메라 모델·펌웨어·광고한 속성·속성 설명 응답을 확인하는 자료이며 사진·시리얼·레시피 이름을 포함하지 않습니다. 이 기능은 레시피 설정과 슬롯 선택을 변경하지 않습니다.
8. 일반 `카메라 연결`이 성공하면 C1~C4의 이름과 설정이 카메라 화면과 일치하는지 확인하고 `카메라 전체 백업`으로 이 앱이 다루는 레시피 설정을 보관합니다. 카메라의 모든 기능을 백업하는 것은 아닙니다.
9. 변경해도 되는 테스트 슬롯 **하나**만 배치하고 적용합니다. 적용 후 카메라에서 값과 결과를 확인하고 백업 복원도 확인한 뒤 다른 슬롯으로 확장하세요. 전송 중에는 케이블을 분리하지 마세요.

연결·조회가 실패하면 **호환성 진단 JSON을 바탕으로 다음 수정을 해야 합니다**. X-M5 1.20 이외의 펌웨어에는 새 예외를 자동 적용하지 않습니다.

Windows에서 GUI 없이 진단 JSON을 저장하려면 실행 파일 폴더의 PowerShell에서:

```powershell
.\fuji_san.exe --diagnose-capabilities xm5-diagnostic.json
```

`--diagnose-slots`는 레시피 값을 쓰지 않지만 슬롯을 순차적으로 선택합니다. 처음 확인에는 `--diagnose-capabilities`를 사용하세요. X-M5에서 원시 쓰기 진단 `--diagnose-write-back`은 차단됩니다.

## X-M5 펌웨어 1.20: 슬롯 전환 진단

실기에서 모델 인식과 레시피 값 읽기는 성공했지만 모든 속성 설명 요청이 `0x2002`로 거부되었습니다. 촬영 모드 다이얼을 C1과 C4로 바꾼 후에도 USB 속성 `d18c`는 모두 `02 00`이었습니다. 따라서 다이얼 위치와 USB 선택값이 같은 번호라고 단정할 수 없습니다.

이 경우 앱의 **도구 → X-M5 슬롯 전환 진단 → 진단 실행**을 이용합니다. 이 검사는 X-M5 1.20에만 제공됩니다. USB의 선택값 1~4를 순서대로 보내고 선택값과 레시피를 읽은 뒤 원래 선택값 복원을 시도합니다. 레시피 설정값이나 이름에 쓰기 명령을 보내지 않습니다. 카메라 한 대만 연결하고 검사 중에는 케이블을 분리하지 마세요. 정상 카메라 연결 버튼을 누르지 않아도 진단을 실행할 수 있습니다.

결과 JSON을 복사해 확인합니다. `originalSelectorRestored`는 선택값 복원 여부, `originalRecipeFieldsUnchanged`는 원래 선택값에서 읽었던 이름과 앱이 다루는 설정값의 보존 여부입니다. 복원이 확인되지 않으면 카메라 상태를 직접 확인해야 합니다. 카메라의 모든 속성 보존을 검사하는 기능은 아닙니다.

`success: true`는 후보 선택값을 보내고 다시 읽는 검사가 통과했다는 뜻입니다. 실제 C1~C4와의 대응이나 레시피 쓰기 지원이 확인된 것은 아닙니다. `physicalCMappingVerified`는 계속 `false`입니다. 이 진단은 레시피 필드를 쓰지 않습니다. 별도의 일반 조회·전송 경로는 X-M5 1.20에 한해 속성 설명의 `0x2002` 오류를 처리합니다. `distinctRecipeSignatures`는 읽은 이름·설정 조합의 종류 수입니다. 보고서에는 레시피 이름과 시리얼이 포함되지 않습니다. 모든 후보에서 동일한 설정을 읽더라도 저장된 레시피가 서로 같은 경우가 있어 그 결과만으로 슬롯 전환 실패를 단정할 수 없습니다.

## X-M5 1.20의 첫 전송 확인

1. 새 앱에서 카메라 연결을 누르고 C1~C4가 읽히는지 확인합니다. 실기 진단의 USB 선택값 1은 Classic Chrome·DR400, 선택값 2~4는 PROVIA·DR100이었습니다. 카메라 화면의 실제 C번호와 비교하세요.
2. 도구의 카메라 전체 백업으로 C1~C4의 레시피 설정을 저장합니다. 모든 카메라 기능을 백업하는 것은 아닙니다.
3. 변경해도 되는 슬롯 하나만 열어 설정 하나를 변경합니다. 예: 앱의 C4가 색농도 0이면 +1로 변경하고 카메라에 저장합니다. 원본 백업이 디스크에 저장된 후 바뀐 항목만 전송하며, 전송 후 해당 값을 다시 읽어 확인합니다.
4. USB를 분리하고 실제 카메라 C4의 값과 다른 C슬롯 보존 여부를 확인합니다. 다른 슬롯이 바뀌면 즉시 멈추고 결과를 공유하세요.
5. 다시 연결해 변경값을 원래 값으로 돌리고 확인합니다. 백업 복원 기능의 실기 검증과는 별개입니다. 슬롯 번호와 단일 항목 쓰기를 확인한 뒤 레시피 하나의 전송·백업 복원을 시험하세요. 모든 항목이 한 번의 단일 설정 테스트로 검증되는 것은 아닙니다.

카메라가 값을 거부하면 해당 속성 번호와 응답을 표시하고 중단합니다. 일부 앞선 설정이 이미 바뀌었을 수 있으며, 자동 롤백을 보장하지 않습니다. 처음부터 여러 슬롯에 일괄 전송하지 마세요.

## 오프라인 프로토콜 검사를 다시 실행하려면

설치된 Dart 실행 파일과 Python으로 실행합니다. Flutter 초기화나 네트워크 연결은 하지 않습니다.

```bash
python tool/offline_protocol_check.py --dart /path/to/dart
```

## 근거

- 원본 코드: https://github.com/reikop/fuji-san/tree/v0.3.0-alpha.1
- X-M5 사용자 설정 C1~C4: https://fujifilm-dsc.com/en-int/manual/x-m5/taking_photo/shooting_mode/
- USB 연결 모드: https://fujifilm-dsc.com/en-int/manual/x-m5/connections/save_load_setting/
- 필름 시뮬레이션 다이얼 C: https://fujifilm-dsc.com/en/manual/x-m5/about_this_camera/parts/index.html

원본의 MIT 라이선스와 서드파티 고지 파일을 유지했습니다. 후지필름 또는 원본 개발자가 배포·검증한 버전은 아닙니다.
