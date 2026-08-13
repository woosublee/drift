# 셀프사인 릴리즈 설계

**상태:** 승인됨

## 목표

Drift에 GitHub Release 기반의 셀프사인 배포와 Sparkle 자동 업데이트 채널을 구축한다. 첫 정식 릴리즈는 `v0.1.0` / build `1`이며, 배포 앱은 arm64와 x86_64를 포함하는 Universal 2 형식이다.

릴리즈 로직은 GitHub Actions 안에 중복 구현하지 않는다. CI와 로컬 fallback이 같은 빌드·패키징·검증 스크립트를 호출하도록 해, 로컬에서 검증한 절차와 실제 게시 절차가 달라지는 문제를 방지한다.

## 조사 결과와 전제

### 현재 준비된 로컬 자산

- Keychain에 유효한 셀프사인 code-signing identity `Drift`가 있다.
- `Drift` 인증서는 2036-08-05까지 유효하다.
- Sparkle Keychain service `https://sparkle-project.org`에 account `com.woosublee.drift.sparkle.ed25519`가 있다.
- `Info.plist`에 Sparkle 공개키가 있다.
- Sparkle의 `sign_update`와 `generate_appcast` 실행 파일은 SwiftPM artifact에 포함되어 있다.

Sparkle private key와 `Info.plist` 공개키가 실제 한 쌍인지는 비밀 키를 출력하지 않는 validator로 구현 과정에서 검증한다.

### 현재 없는 자산과 기능

- `Developer ID Application`, `Apple Development`, `Apple Distribution` 인증서
- Apple notarization 설정
- Drift GitHub 저장소의 릴리즈 secrets
- DMG와 appcast 생성 절차
- GitHub Actions 릴리즈 workflow
- 버전의 단일 소스와 build monotonicity 검사
- 게시 전후 릴리즈 산출물 일관성 검증

따라서 이번 설계는 Apple notarization이 아닌 셀프사인 채널을 대상으로 한다. 신규 설치 시 Gatekeeper 경고가 발생할 수 있다는 점을 사용자 문서에 명시한다.

## 참고 구현

Drift에는 한 저장소의 구현을 그대로 복제하지 않고 다음 패턴을 결합한다.

### CLIProxyManager에서 채택

- `release/version.json`을 canonical version source로 사용
- version resolver와 `Info.plist` sync/check 분리
- 이전 appcast보다 build number가 커야 하는 monotonicity 검사
- source, app, DMG, appcast, tag, provenance의 version/build parity 검사
- versioned DMG와 `release-provenance.json`
- 빌드 전후 tag와 Release 경합 검사
- CI와 로컬 fallback의 공용 릴리즈 스크립트

### Quill에서 채택

- Sparkle private/public key 일치 validator
- `sign_update` 결과의 `--verify` 재검증
- 셀프사인 `.p12`를 CI 임시 Keychain에 import하는 방식
- Sparkle nested components를 먼저 서명하는 순서
- 추후 Developer ID와 notarization workflow를 별도 채널로 추가할 수 있는 구조

### Drift에서 유지

- production과 development의 제품명·Bundle ID 분리
- development 번들에서 `SUFeedURL`과 `SUPublicEDKey` 제거
- Sparkle nested XPC, updater, framework를 순서대로 서명하는 기존 구조
- signing xattr 제거와 designated requirement 검증
- 로컬 셀프사인 인증서 profile 검증 테스트

## 범위

### 포함

- `release/version.json` 기반 버전 단일 소스
- `Info.plist` 버전 동기화와 불일치 검사
- Universal 2 production 앱 빌드
- hardened runtime을 적용한 셀프사인 앱과 DMG
- GitHub Release용 versioned DMG
- Sparkle EdDSA 서명을 포함한 appcast
- 릴리즈 provenance
- 게시 전후 artifact 검증
- tag 기반 GitHub Actions 릴리즈
- 안전한 `workflow_dispatch` dry-run과 명시적 publish
- 동일 스크립트를 사용하는 로컬 dry-run 및 publish fallback
- 첫 릴리즈 게시 전 별도 사용자 확인
- 셀프사인 설치·업데이트 운영 문서

### 제외

- Apple Developer ID 코드 서명과 notarization
- beta 또는 prerelease용 별도 Sparkle 채널
- Sparkle key 또는 code-signing 인증서 회전 자동화
- `.pkg` 배포
- App Store 배포
- 자동 changelog 생성
- `generate_appcast`가 관리하는 장기 release archive

## 버전과 릴리즈 식별자

`release/version.json`이 버전의 유일한 수정 지점이다.

```json
{
  "marketingVersion": "0.1.0",
  "buildNumber": 1
}
```

resolver는 이 파일에서 다음 값을 파생한다.

| 값 | 첫 릴리즈 |
|---|---|
| Marketing version | `0.1.0` |
| Build number | `1` |
| Git tag | `v0.1.0` |
| DMG 파일명 | `Drift-0.1.0.dmg` |
| Production Bundle ID | `com.woosublee.drift` |

`Info.plist`는 저장소에 동기화된 값을 유지한다. sync 명령은 `release/version.json`의 값을 기록하고, check 명령은 불일치 시 실패한다. Makefile이나 임의 environment variable로 version, build, tag, production Bundle ID를 override하지 않는다.

Git 태그는 `v<marketingVersion>` 형식이다. Sparkle에서 `sparkle:shortVersionString`은 marketing version, `sparkle:version`은 build number를 사용한다.

## 아키텍처와 구성 요소

각 구성 요소는 독립 스크립트 또는 명확한 Make target으로 제공한다. 하위 명령은 결과를 표준화된 environment 또는 machine-readable output으로 전달하며, 동일 계산을 여러 곳에서 다시 구현하지 않는다.

### Version resolver와 synchronizer

책임:

- version JSON의 schema와 값 검증
- marketing version, build number, tag, artifact 이름, URL 계산
- `Info.plist` 동기화와 check
- 태그와 marketing version 일치 검사

의존성:

- `release/version.json`
- source `Info.plist`
- 저장소의 GitHub owner/repo 정보

### Universal 2 builder

책임:

- arm64와 x86_64 실행 파일을 각각 release mode로 빌드
- `lipo`로 앱 executable을 Universal 2로 결합
- production `.app` 구조 생성
- Sparkle framework와 nested helper 포함
- production feed URL과 공개키 주입
- development identity 분리 규칙 유지

의존성:

- SwiftPM
- 기존 Makefile의 번들 조립 로직
- Sparkle artifact
- version resolver 출력

### Signing and packaging

책임:

- Sparkle nested XPC, updater, autoupdate, framework를 먼저 서명
- 최종 앱에 hardened runtime을 적용해 서명
- 앱 서명과 designated requirement 검증
- versioned DMG 생성 및 DMG 코드 서명

로컬 기본 identity는 `Drift`다. CI는 GitHub secret에서 복원한 `.p12`를 임시 Keychain에 import해 같은 identity를 사용한다.

이번 범위에서는 필요성이 확인되지 않은 entitlement를 추가하지 않는다. 특히 `disable-library-validation`은 실제 실행 또는 검증 실패로 필요성이 입증되기 전에는 넣지 않는다.

### Sparkle appcast generator

책임:

- 로컬 Keychain 또는 CI secret에서 Sparkle private key를 취득
- private key에서 파생한 공개키와 `Info.plist` 공개키 일치 검사
- `sign_update`로 DMG의 EdDSA signature 생성
- `sign_update --verify`로 signature 재검증
- GitHub Release download URL을 enclosure로 가진 XML 생성
- XML을 atomic하게 교체

첫 릴리즈의 feed와 enclosure URL은 다음 형식이다.

- Feed: `https://github.com/woosublee/drift/releases/latest/download/appcast.xml`
- Enclosure: `https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg`

정식 non-prerelease만 `latest` feed 대상이 된다.

### Artifact verifier

책임:

- source와 `release/version.json` 일치
- 태그와 marketing version 일치
- 앱의 marketing version, build number, Bundle ID 확인
- executable이 arm64와 x86_64를 모두 포함하는지 확인
- Sparkle nested components와 앱의 code signature 검증
- DMG mount 후 내부 앱을 다시 검증
- appcast의 version, build, URL, 파일 길이, EdDSA signature 검증
- provenance와 source/app/DMG/appcast의 parity 검증
- 기존 공개 appcast보다 build number가 큰지 확인

### Publish adapters

GitHub Actions와 로컬 fallback은 게시 방식만 담당한다. build, signing, appcast, verification 로직은 공용 스크립트를 호출한다.

- GitHub Actions는 `v*` tag 또는 `workflow_dispatch`로 실행한다.
- 로컬 fallback은 기본 dry-run이며 `--publish`를 명시해야 외부 상태를 변경한다.
- 게시 직전 원격 tag, Release, latest appcast를 다시 조회해 경합을 방지한다.

## 산출물

정식 Release에는 다음 세 파일만 게시한다.

1. `Drift-0.1.0.dmg`
2. `appcast.xml`
3. `release-provenance.json`

provenance에는 비밀 정보를 포함하지 않고 다음 공개 메타데이터만 기록한다.

- marketing version과 build number
- tag
- commit SHA
- production Bundle ID
- CPU architectures
- artifact 파일명, byte length, SHA-256
- appcast enclosure URL
- code-signing certificate 표시명과 공개 메타데이터인 SHA-256 certificate fingerprint
- Sparkle 공개키
- build timestamp와 workflow run 식별자

## CI 릴리즈 흐름

### 태그 기반 정식 게시

1. `release/version.json`과 `Info.plist` 동기화 상태를 검사한다.
2. tag와 marketing version이 일치하는지 검사한다.
3. 원격에 동일 Release가 없는지 확인한다.
4. 공개 appcast가 있다면 build monotonicity를 검사한다.
5. 전체 테스트를 실행한다.
6. CI 임시 Keychain을 만든다.
7. 셀프사인 certificate를 import한다.
8. Universal 2 production 앱을 빌드하고 서명한다.
9. DMG를 생성하고 서명한다.
10. Sparkle key pair를 검증하고 appcast를 생성한다.
11. provenance를 생성한다.
12. 세 artifact를 전체 검증한다.
13. 게시 직전 현재 tag가 release commit을 가리키는지와 원격 tag, Release, appcast 상태를 다시 확인한다.
14. 기존 tag를 대상으로 GitHub Release를 만들고 artifact를 업로드한다.
15. 게시된 artifact를 다시 다운로드해 checksum과 Sparkle signature를 검증한다.
16. `releases/latest/download/appcast.xml`이 게시된 appcast를 반환하는지 확인한다.

### `workflow_dispatch`

기본값은 dry-run이다. 이 모드에서는 build, signing, packaging, verification과 Actions artifact 업로드까지만 수행하고 GitHub Release를 생성하지 않는다.

명시적인 publish Boolean input이 있을 때만 게시 단계를 실행한다. 이때 workflow 실행 ref는 `refs/tags/v<marketingVersion>`이어야 하고, 해당 tag가 현재 workflow commit을 가리켜야 한다. 수동 dispatch가 새 tag를 만들지는 않는다. publish 실행에도 tag/version 일치와 원격 경합 검사가 동일하게 적용된다.

## 로컬 fallback 흐름

로컬 fallback은 다음 자산을 사용한다.

- Keychain code-signing identity `Drift`
- Sparkle service `https://sparkle-project.org`
- Sparkle account `com.woosublee.drift.sparkle.ed25519`

기본 실행은 dry-run이다. 테스트, Universal 2 build, signing, DMG, appcast, provenance, 전체 검증까지 수행하지만 tag나 Release는 만들지 않는다.

`--publish`를 명시한 경우에만 외부 게시를 수행한다. 로컬 fallback은 release commit에 해당하는 annotated tag가 이미 로컬과 원격에 동일하게 존재하는지 확인하며, tag를 자동 생성하거나 push하지 않는다. 검증된 tag를 대상으로만 `gh release create` 또는 부분 업로드 재개를 수행한다. publish 전에 다음을 확인한다.

- working tree가 clean인지
- 현재 commit이 사용자가 의도한 release commit인지
- version/tag가 일치하는지
- 원격에 예상하지 않은 tag 또는 Release가 없는지
- 기존 appcast build보다 새 build가 큰지
- 로컬 artifact 검증이 완료됐는지

첫 `v0.1.0` 게시 전에는 dry-run과 CI dry-run 결과를 제시하고 사용자에게 별도 확인을 받는다.

## GitHub secrets와 Keychain

GitHub Actions는 다음 repository secrets를 사용한다.

| Secret | 용도 |
|---|---|
| `DRIFT_CERTIFICATE_BASE64` | 셀프사인 `Drift` identity를 포함한 `.p12` |
| `DRIFT_CERTIFICATE_PASSWORD` | `.p12` export/import 비밀번호 |
| `SPARKLE_PRIVATE_KEY` | Drift Sparkle Ed25519 private key |

보안 규칙:

- private key, `.p12`, 비밀번호를 Git에 저장하지 않는다.
- workflow와 스크립트는 secret 값을 stdout/stderr에 출력하지 않는다.
- shell tracing을 활성화하지 않는다.
- secret 입력은 GitHub mask 대상에 추가한다.
- 임시 `.p12`와 Keychain은 성공·실패와 관계없이 cleanup한다.
- build artifact와 provenance에 private material이 없는지 검사한다.
- 인증서 export와 secret 등록은 대화 중 값을 모델 응답이나 로그에 노출하지 않는 방식으로 수행한다.

## 실패 처리와 재개 정책

릴리즈는 fail-closed 원칙을 따른다.

### 게시 전 실패

다음 중 하나라도 실패하면 tag 또는 Release를 게시하지 않는다.

- 테스트
- version, tag, build monotonicity 검사
- Universal 2 architecture 검사
- app 또는 DMG code signature
- Sparkle private/public key 일치 검사
- `sign_update --verify`
- appcast parsing과 enclosure 검증
- provenance parity

### 경합과 기존 Release

- 예상하지 않은 기존 tag나 Release를 덮어쓰거나 삭제하지 않는다.
- 게시 직전 원격 상태를 다시 확인한다.
- 기존 공개 appcast보다 build number가 같거나 작으면 중단한다.
- prerelease는 stable `latest` feed에 사용하지 않는다.

### 부분 게시 재개

- 원격 artifact와 로컬 artifact의 SHA-256이 같을 때만 완료된 업로드로 인정한다.
- 같은 checksum의 artifact는 재업로드하지 않고 나머지만 재개할 수 있다.
- 파일명은 같지만 checksum이 다르면 자동 교체하지 않고 중단한다.
- Release metadata가 예상과 다르면 자동 수정하지 않고 사용자 판단을 요청한다.

### 외부 API 오류

조회와 다운로드 같은 idempotent GitHub API 호출은 제한적으로 재시도한다. tag 생성, Release 생성, asset 교체 같은 외부 변경은 상태를 재조회한 뒤 한 번만 수행한다.

## 셀프사인 신뢰 모델

신규 사용자는 Apple notarization이 없기 때문에 최초 실행 시 Gatekeeper 경고를 볼 수 있다. 이후 업데이트 신뢰는 다음 두 자산의 연속성에 의존한다.

1. 동일한 `Drift` code-signing certificate
2. 동일한 Sparkle Ed25519 key pair

두 private 자산의 분실 또는 무단 교체는 기존 설치의 업데이트 신뢰를 훼손할 수 있다. 이번 범위에서는 key rotation을 자동화하지 않으며, 백업·회전·폐기 절차는 별도의 운영 작업으로 다룬다.

추후 Developer ID를 확보하면 notarized workflow를 별도 추가한다. 그때도 version resolver, Universal 2 build, appcast, provenance, artifact verification 계층은 재사용하고 code-signing 및 notarization 단계만 교체한다.

## 검증 전략

### 정적·단위 검증

- 올바른 version JSON을 resolver가 예상 값으로 변환하는지 확인
- 잘못된 semver와 build number를 거부하는지 확인
- tag와 marketing version 불일치를 거부하는지 확인
- `release/version.json`과 `Info.plist` 불일치를 탐지하는지 확인
- appcast의 version, short version, URL, byte length, signature parsing 확인
- 기존 appcast보다 build가 증가하지 않으면 실패하는지 확인
- workflow의 secret 이름과 공용 script interface가 일치하는지 확인
- 기존 Swift unit/integration test 유지

### 로컬 통합 dry-run

- arm64와 x86_64 binary를 만들고 Universal 2 executable인지 확인
- nested Sparkle code와 앱에 `codesign --verify --deep --strict` 수행
- production Bundle ID와 designated requirement 확인
- DMG mount 후 내부 앱을 재검증
- Sparkle private/public key 일치 확인
- `sign_update --verify` 수행
- DMG checksum, byte length와 appcast enclosure 일치 확인
- provenance와 source/app/DMG/appcast parity 확인
- development 앱에 update metadata가 없음을 확인
- production 앱에 정확한 feed URL과 공개키가 있음을 확인

### CI dry-run

- `workflow_dispatch` 기본 모드로 secrets import를 확인
- Universal 2 build, signing, DMG, appcast, provenance 생성 확인
- Actions artifact에 세 파일이 포함되는지 확인
- workflow가 Release를 생성하지 않았는지 확인
- 로그와 Actions artifact에 secret material이 없는지 확인

### 게시 후 검증

- 게시된 세 artifact를 다시 다운로드
- local verified artifact와 SHA-256 비교
- DMG의 code signature와 내부 앱 재검증
- Sparkle EdDSA signature 재검증
- appcast enclosure URL이 실제 versioned DMG를 반환하는지 확인
- release tag, version, build, provenance 일치 확인
- `releases/latest/download/appcast.xml`이 동일 appcast를 반환하는지 확인

## 문서화

README 또는 별도 release 문서에 다음을 기록한다.

- 버전 증가와 `Info.plist` sync 절차
- 로컬 dry-run과 publish 명령
- GitHub Actions dry-run과 tag 기반 publish 절차
- 필요한 GitHub secret 이름과 안전한 등록 방식
- 셀프사인 앱의 최초 설치와 Gatekeeper 안내
- 릴리즈 실패 시 재개 가능한 조건
- 인증서와 Sparkle key 연속성의 중요성
- Developer ID/notarization은 별도 후속 범위라는 점

## 완료 기준

- `release/version.json`이 버전의 단일 소스로 동작한다.
- `Info.plist`, tag, app, DMG, appcast, provenance가 version/build에 대해 일치한다.
- Universal 2 production 앱과 versioned DMG가 생성된다.
- 앱과 DMG의 셀프사인 signature가 검증된다.
- Sparkle private/public key 일치와 DMG EdDSA signature가 검증된다.
- 로컬 dry-run이 외부 상태 변경 없이 통과한다.
- GitHub Actions dry-run이 Release를 만들지 않고 통과한다.
- 잘못된 tag, 낮거나 같은 build, key 불일치, artifact 불일치가 fail-closed로 처리된다.
- workflow 로그와 artifact에 private key, `.p12`, 비밀번호가 없다.
- 릴리즈 운영과 셀프사인 최초 실행 안내가 문서화된다.
- 첫 `v0.1.0` 게시 직전에 사용자의 별도 승인을 받는다.
- 게시 후 세 artifact와 stable appcast URL을 재검증한다.
