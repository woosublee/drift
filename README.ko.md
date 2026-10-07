# Drift

[English](README.md)

> macOS를 위한 조용하고 세밀하게 설정 가능한 커서 자동화 도구.

Drift는 사용자의 실제 입력이 없는 시간을 기다린 뒤 설정된 커서 이동과 선택적 클릭을 실행하는 native macOS 메뉴 막대 앱입니다. Dock이나 일반 앱 창을 차지하지 않으며, 실제 키보드 또는 마우스 입력이 발생하면 즉시 자동 동작을 중단합니다. 모든 설정은 사용자의 Mac에 로컬로 저장됩니다.

**macOS 13+ · Swift 5.10 · SwiftUI · Swift Package Manager**

## 핵심 기능

- **메뉴 막대 전용 앱** — Dock icon이나 일반 앱 창 없이 compact popover로 실행됩니다.
- **유휴 상태 기반 자동화** — `Start Moving After`와 `Move Every`로 시작 시점과 반복 간격을 설정합니다.
- **세 가지 이동 방식** — Silent는 거의 보이지 않는 짧은 왕복 이동, Standard는 화면 안의 선형 이동, Natural은 시간 변화가 포함된 부드러운 곡선 이동을 사용합니다.
- **선택적 클릭** — 저장된 화면 위치에서 Left, Right, Alternating 클릭을 실행하고 cursor를 원래 위치로 돌려놓습니다.
- **자동 중지 조건** — 선택한 시각 또는 설정한 배터리 잔량 아래에서 자동으로 비활성화할 수 있습니다.
- **빠른 제어** — popover, global shortcut, Launch at Login으로 Drift를 제어합니다.
- **실제 입력 우선** — 사용자의 마우스 또는 키보드 입력이 발생하면 진행 중인 자동 동작을 취소하고 idle timer를 다시 시작합니다.
- **로컬 중심 동작** — 기본 local build에는 analytics, account, application network request가 없습니다.

## 동작 방식

1. 메뉴 막대 popover에서 **Active**를 켭니다.
2. 설정한 유휴 시간이 지날 때까지 기다립니다.
3. 유효한 display 영역 안에서 선택한 이동 또는 click sequence를 실행합니다.
4. 설정한 반복 간격을 기다린 뒤 다음 sequence를 실행합니다.
5. 실제 키보드 또는 마우스 입력이 발생하면 자동 동작을 즉시 취소하고 새로운 유휴 대기를 시작합니다.

## 개인정보 보호와 권한

Drift가 cursor를 움직이고 선택적 click을 실행하려면 macOS Accessibility 권한이 필요합니다. `Drift`와 `Drift Dev`는 서로 다른 Bundle ID를 사용하므로 macOS가 각 앱의 권한과 설정을 독립적으로 관리합니다.

Drift에는 analytics가 없습니다. Production release는 Sparkle 2.9.2를 사용해 stable release feed의 서명된 업데이트를 제공합니다. Production artifact는 Developer ID Application 인증서로 서명되고 Apple notarization을 거치며, notarization ticket은 앱과 DMG 모두에 staple됩니다. Development bundle에는 feed URL과 Sparkle public key가 모두 포함되지 않습니다. dry-run과 공개 배포 안전장치를 포함한 운영 절차는 [release runbook](docs/releasing.md)을 참고하세요.

## 릴리즈 설치

[GitHub Releases](https://github.com/woosublee/drift/releases)에서 DMG를 다운로드하고 `Drift.app`을 응용 프로그램 폴더로 드래그한 다음 실행하세요. 0.1.6 이하 릴리즈는 self-signed였습니다. 해당 버전에서 Sparkle로 업데이트하는 것은 정상 동작하지만, 서명 identity가 바뀌었기 때문에 Accessibility 권한을 한 번 다시 허용해야 합니다. Drift가 실행되면 메뉴 막대 아이콘을 사용하세요. 의도적으로 Dock icon이나 일반 앱 창은 표시하지 않습니다.

## 빌드 및 실행

### 요구사항

- macOS 13 이상
- Xcode Command Line Tools
- Swift 5.10 이상

저장소를 clone하고 test를 실행합니다.

```bash
git clone https://github.com/woosublee/drift.git
cd drift
swift test
```

Bundle은 기본적으로 maintainer의 `Developer ID Application` identity로 서명되며, 덕분에 다시 빌드해도 Accessibility 승인이 유지됩니다. identity가 사용 가능한지 확인합니다.

```bash
make check-signing-identity
```

해당 identity가 없다면 `CODESIGN_IDENTITY=-`로 ad-hoc 서명을 사용하세요.

`Drift Dev`를 빌드하고 검증합니다.

```bash
make verify-app \
  CONFIGURATION=debug \
  BUILD_DIR=/tmp/drift-bundles/dev

open "/tmp/drift-bundles/dev/Drift Dev.app"
```

## 빌드 variant

| Variant | App | Bundle ID | 기본 configuration |
|---|---|---|---|
| Production | `Drift.app` | `com.woosublee.drift` | `release` |
| Development | `Drift Dev.app` | `com.woosublee.drift.dev` | `debug` |

`APP_VARIANT=production|dev`를 지정하면 Swift build configuration과 독립적으로 app identity를 선택할 수 있습니다. UserDefaults, Accessibility 승인, Login Items, LaunchServices는 Bundle ID를 기준으로 분리됩니다.

## 개발 및 검증

fresh test suite를 실행합니다.

```bash
swift package clean
swift test
```

두 signed identity를 검증합니다.

```bash
make verify-app \
  CONFIGURATION=debug \
  BUILD_DIR=/tmp/drift-bundles/dev

make verify-app \
  CONFIGURATION=release \
  BUILD_DIR=/tmp/drift-bundles/production
```

사용자가 직접 수행하는 macOS 검증 항목은 [docs/manual-verification.md](docs/manual-verification.md)에 정리되어 있습니다. 체크되지 않은 항목은 자동 검증 통과로 간주하지 않습니다.
