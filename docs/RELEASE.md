# 릴리스 자동화

이 Mac에서 다음 한 명령으로 테스트 → 소스 빌드 → Developer ID 서명 → Apple 공증 → 업데이트 서버 배포 → HTTPS 파일 검증을 실행합니다.

```sh
./scripts/release.sh
```

GitHub 릴리스와 ZIP·SHA-256 첨부까지 함께 게시하려면 다음을 사용합니다. 기존 공개 릴리스와 같이 **prerelease**로 게시합니다.

```sh
./scripts/release.sh --github
```

이번 버전부터 Homebrew tap도 함께 갱신하려면 다음 명령을 사용합니다. `--homebrew`는 `--github`를 포함합니다.

```sh
./scripts/release.sh --homebrew
```

`ynifamily3/homebrew-tap`의 `Casks/typing-pet.rb`를 갱신하며, 공개 GitHub ZIP·체크섬이 준비한 파일과 같은지 먼저 확인합니다.
일반 사용자의 설치 명령은 `brew tap ynifamily3/tap` 후 `brew install --cask ynifamily3/tap/typing-pet`입니다.

## 새 버전 준비

1. 개발과 수동 UI 확인을 마칩니다. 스크립트는 UI나 입력 모니터링 권한을 자동으로 조작하지 않습니다.
2. 저장소 루트의 `version.json`에서 `version`과 `build`를 **둘 다** 현재 배포보다 높입니다. 예를 들어 다음 릴리스는 다음과 같습니다.

   ```json
   {
     "version": "0.15.1",
     "build": 25
   }
   ```

3. `CHANGELOG.md` 맨 위에 `## 0.15.1 - YYYY-MM-DD` 섹션과 변경 내용을 넣습니다. 이 내용이 자동 업데이트 안내와 GitHub 릴리스 노트가 됩니다. 설치 안내의 버전 링크도 새 버전에 맞게 준비합니다.
4. 소스·버전·문서를 커밋합니다. `--github`를 쓸 때는 먼저 해당 커밋을 GitHub에 push합니다. 스크립트는 소스를 자동 커밋하거나 push하지 않습니다.
5. 읽기 전용 사전 점검 후 릴리스합니다.

   ```sh
   ./scripts/release.sh --dry-run --homebrew
   ./scripts/release.sh --homebrew
   ```

기본적으로 커밋되지 않은 변경이 있으면 중단합니다. GitHub 게시 없이 로컬 소스를 배포할 때에만 `--allow-dirty`로 허용할 수 있습니다. 이 경우에도 준비 이후 소스가 바뀌면 재시도를 거부합니다.
`version.json`은 일반 개발 빌드의 기본 버전에도 쓰입니다. 기존 테스트용 `TYPINGPET_VERSION`·`TYPINGPET_BUILD` 재정의는 `build_app.sh`에서 계속 지원합니다.

## 기존 설정 사용

- Keychain에 유효한 `Developer ID Application` 인증서와 개인 키가 있어야 합니다. 인증서가 여러 개면 `CODE_SIGN_IDENTITY`에 인증서의 전체 이름을 지정합니다.
- 공증 자격 증명은 기존 Keychain 프로필 `typingpet-notary`를 사용합니다. 다른 이름은 `NOTARY_KEYCHAIN_PROFILE`로 지정합니다. 실명·Team ID는 서명된 앱의 공개 정보입니다.
- 업데이트 키는 기존 `~/.config/typingpet/update-keys/production.key`와 `production.pub`를 사용합니다. `TYPINGPET_UPDATE_KEY_DIR`로 디렉터리를 바꿀 수 있습니다. **릴리스 과정에서 키를 새로 만들지 않습니다.** 현재 배포 ZIP의 서명도 확인해 다른 키로 바뀌었으면 중단합니다.
- 정적 업데이트 서버의 기존 폴더 `~/TypingPetUpdate`를 사용합니다. `TYPINGPET_UPDATE_ROOT`로 바꿀 수 있습니다. nginx·DNS·TLS 설정은 변경하지 않습니다. 로컬 feed와 `https://pet.miel.ing/update/production/latest.json`이 같아야 진행합니다.
- GitHub 옵션에는 로그인된 `gh` CLI가 필요합니다. 비밀번호·앱 전용 암호·토큰은 스크립트 인자로 받거나 저장하지 않습니다.
- Homebrew 옵션은 기존 공개 tap 저장소에 대한 쓰기 권한이 필요합니다. 처음 tap 저장소를 만든 뒤 사용하세요. 기존과 같은 버전의 다른 파일이나 더 낮은 버전으로 cask를 덮어쓰지 않습니다.

처음 인증서를 준비하는 방법은 [Developer ID](DEVELOPER_ID.md)를 참고하세요.

## 실행 단계와 산출물

1. 버전·빌드·변경 내용·소스 상태·인증서·업데이트 키 파일·현재 feed를 확인합니다. `--dry-run`은 여기까지만 읽기 전용으로 수행하며, 키 쌍의 암호학적 검사와 공증 자격 증명 검사는 실제 실행에서 합니다.
2. 기존 업데이트 키 쌍과 현재 배포 ZIP 서명을 검사하고, `notarytool history`로 공증 프로필을 확인합니다.
3. `swift test`, `check_todo.sh`, `check_publish_update.sh`를 실행합니다. 실패하면 빌드·공증·배포로 넘어가지 않습니다. 릴리스 스크립트 자체의 보호 조건 테스트는 CI에서 별도로 실행합니다.
4. Apple Silicon용 release 앱을 빌드합니다. 프로덕션 앱에서는 로컬 소스 디렉터리의 이미지 검색 코드를 제외하고 디버그 심볼을 제거한 뒤 Developer ID로 서명합니다.
5. 공증 결과가 `Accepted`일 때만 staple·ticket 검증·Gatekeeper 검사를 수행합니다. 기본 대기 한도는 30분이며 `NOTARY_TIMEOUT`으로 바꿀 수 있습니다.
6. Ed25519로 서명한 업데이트 ZIP과 manifest를 생성합니다. GitHub용 이름의 ZIP도 **같은 바이트**를 복사해 사용합니다. 개인 키 파일·알려진 토큰 패턴·바이너리의 `/Users/<이름>/` 경로가 발견되면 게시 전에 중단합니다. 이 검사는 모든 형태의 비밀정보를 탐지한다고 보장하지 않습니다.
7. GitHub 옵션 사용 시 먼저 draft 릴리스를 준비합니다. 태그는 정확한 소스 커밋을 가리켜야 하며 기존 태그를 옮기지 않습니다.
8. 서버의 동시 배포를 잠그고 ZIP을 먼저 복사한 뒤 `latest.json`을 원자적으로 교체합니다. 버전별 ZIP은 덮어쓰지 않습니다. 같은 Mac에서 실제 HTTPS URL로 manifest와 ZIP을 받아 배포 파일과 비교합니다. 이는 독립적인 외부망 접속 검증과는 구분됩니다.
9. 서버 검증이 끝나면 GitHub draft를 공개합니다. 공개된 GitHub 첨부 파일은 덮어쓰지 않습니다.
10. Homebrew 옵션 사용 시 공개 GitHub ZIP·체크섬을 다시 받아 준비된 파일과 비교하고, 버전과 SHA-256이 고정된 cask를 게시합니다. 이미 같은 내용이면 재시도는 아무것도 변경하지 않습니다.

산출물은 `dist/releases/v<버전>-<빌드>/`에 남습니다.

- `TypingPet.app`, 공증된 ZIP, 업데이트 feed와 서명 ZIP
- `TypingPetMac-v<버전>-arm64.zip`와 `.sha256`
- `release-notes.md`, `notary-result.json`, `release.log`
- 이전 feed의 `previous-latest.json`, 준비 완료 증거 `ready.json`, 게시 완료 기록 `complete.json`
- Homebrew 옵션 사용 시 공개한 `typing-pet.rb`

`dist/`와 키·인증서 파일 형식은 Git에서 제외합니다. 경로 제거는 앞으로 생성하는 바이너리에 적용됩니다. 과거 GitHub ZIP, 커밋 작성자의 실명·이메일, 서명 인증서의 공개 신원은 자동 변경하지 않습니다.

## 게시 전 멈추기와 재시도

공증과 패키징까지만 마치고 검토할 수 있습니다.

```sh
./scripts/release.sh --prepare-only
# 산출물 확인 후, 같은 소스에서 저장된 ZIP을 그대로 배포
./scripts/release.sh --resume --github
```

Homebrew까지 게시하거나 tap 게시만 재시도할 때는 `./scripts/release.sh --resume --homebrew`를 사용합니다.
이 시점에 업데이트 서버와 GitHub가 이미 공개됐을 수 있으므로, 같은 산출물을 유지한 채 재시도하세요.

`--resume`은 `ready.json`이 있는 준비 완료 릴리스에만 적용합니다. 테스트·빌드·공증·ZIP 재생성 없이 같은 파일을 재사용합니다. 소스 커밋·소스 내용·ZIP·manifest가 달라졌으면 중단합니다.

서버 배포 후 URL 검증이나 GitHub 공개가 실패하면 업데이트 feed가 이미 새 버전일 수 있습니다. 서버 상태를 확인하고 같은 명령에 `--resume`을 붙이세요. 공개된 버전의 파일을 수정하거나 빌드 번호를 재사용하지 마세요.
이전 manifest는 복구 참고용으로 보관하며 자동 롤백하지 않습니다. 새 버전을 이미 받은 앱에는 더 높은 빌드 번호의 수정 릴리스를 게시해야 합니다.

공증 실패·시간 초과처럼 `ready.json` 생성 전 중단된 경우에는 `release.log`와 `notary-result.json`을 먼저 확인하세요. 시간 초과 뒤에도 Apple에서 처리가 계속될 수 있습니다. submission ID가 있다면 기존 Keychain 프로필로 `xcrun notarytool info <ID> --keychain-profile typingpet-notary`와 `log`를 확인합니다. 실패한 폴더를 별도 이름으로 보관한 뒤 다시 실행하세요. 스크립트는 실패 기록을 지우거나 기존 폴더를 자동 덮어쓰지 않습니다.

## 자동화 자체 검증

```sh
python3 -m unittest discover -s scripts -p 'test_release.py'
./scripts/check_publish_update.sh
```

이 검증은 임시 폴더와 개발 키를 사용하며 실제 Apple 공증·GitHub 게시·프로덕션 배포를 수행하지 않습니다.
