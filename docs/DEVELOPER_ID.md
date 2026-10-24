# Developer ID 정식 배포 준비

TypingPet을 Gatekeeper 경고 없이 배포하고 자동 업데이트 뒤에도 입력 모니터링 권한을 유지하려면 Apple Developer Program 멤버십과 `Developer ID Application` 인증서가 필요합니다.
이 문서는 계정 소유자(Account Holder)가 직접 진행하는 단계입니다.

## 1. 가입 전 준비

- 2단계 인증을 켠 Apple 계정. 개인 프로젝트이므로 회사 계정이 아닌 개인 Apple 계정을 권장합니다.
- Apple 계정의 이름과 성은 **법적 실명**이어야 합니다. 별명이나 회사명을 쓰면 승인이 늦어집니다.
- 실제 주소와 전화번호. 사서함 주소는 받지 않습니다.
- 결제 카드. 연회비는 99 USD이며 가입 화면에서 원화 금액을 보여 줍니다.

개인으로 가입하면 개발자 이름이 실명으로 표시됩니다.
단체로 가입하려면 법인, D-U-N-S 번호, 조직 도메인 이메일, 공개 웹사이트가 필요합니다. 이 앱은 개인 가입으로 충분합니다.

## 2. 가입

1. <https://developer.apple.com/programs/enroll/>에서 **Start your enrollment**를 누릅니다. Mac이나 iPhone의 **Apple Developer** 앱에서도 가입할 수 있으며, 앱으로 하면 신원 확인이 더 빠른 경우가 많습니다.
2. Apple 계정으로 로그인하고 **Individual / Sole Proprietor**를 선택합니다.
3. 실명, 주소, 전화번호를 입력하고 Apple Developer Program License Agreement에 동의합니다.
4. 멤버십을 결제합니다.
5. 승인 메일을 기다립니다. 보통 하루에서 이틀 걸리며, Apple이 전화나 메일로 신원을 확인할 수 있습니다.

승인되면 <https://developer.apple.com/account>의 **Membership details**에서 10자리 **Team ID**를 확인합니다.

## 3. Developer ID Application 인증서

인증서는 Account Holder만 만들 수 있고, 한 계정에 최대 5개까지 만들 수 있습니다.

### Xcode로 만들기 (간단함)

1. Xcode > Settings > Accounts에서 Apple 계정을 추가합니다.
2. 팀을 선택하고 **Manage Certificates…**를 누릅니다.
3. 왼쪽 아래 `+` > **Developer ID Application**을 선택합니다.

### 웹에서 만들기

1. Keychain Access > Certificate Assistant > **Request a Certificate From a Certificate Authority…**를 선택합니다. 이메일과 이름을 넣고 **Saved to disk**를 골라 `.certSigningRequest` 파일을 저장합니다.
2. <https://developer.apple.com/account/resources>에서 Certificates > `+` > Software의 **Developer ID** > **Developer ID Application**을 선택합니다.
3. 저장한 CSR 파일을 올리고 `.cer` 파일을 내려받은 뒤 두 번 눌러 설치합니다.

### 확인과 백업

```sh
security find-identity -v -p codesigning
```

`Developer ID Application: 이름 (TEAMID)`가 보이면 됩니다.
Keychain Access의 My Certificates에서 인증서와 개인 키를 함께 `.p12`로 내보내 안전한 곳에 백업하세요.
개인 키를 잃으면 새 인증서를 만들어야 합니다. Team ID가 같으면 업데이트와 권한은 계속 유지됩니다.

## 4. 공증 자격 증명

1. <https://account.apple.com>의 로그인 및 보안 > **앱 전용 암호**에서 `typingpet-notary` 암호를 만듭니다.
2. 터미널에서 한 번 실행합니다. 암호를 물으면 앱 전용 암호를 넣습니다.

```sh
xcrun notarytool store-credentials typingpet-notary --apple-id "Apple 계정 이메일" --team-id "TEAMID"
```

자격 증명은 Keychain에 저장되며 저장소에는 남지 않습니다.

## 5. Team ID 확인과 업데이트 키 생성

`scripts/build_app.sh`는 `Developer ID Application: 이름 (TEAMID)`에서 Team ID를 읽어 Info.plist의 `TypingPetTeamIdentifier`에 넣습니다.
다른 값을 쓰려면 `TYPINGPET_TEAM_ID`를 지정합니다.
프로덕션 앱은 같은 Team ID로 서명되고 공증된 업데이트만 설치합니다.

첫 프로덕션 빌드를 배포하기 전에만 업데이트 파일 서명용 키를 한 번 만듭니다.

```sh
swift scripts/update_keys.swift generate production
```

`~/.config/typingpet/update-keys/production.key`는 인증서 `.p12`와 함께 백업하세요. 이 키를 잃으면 이미 배포한 앱이 새 업데이트를 받지 못합니다.
이미 배포된 빌드가 있다면 새 키를 만들지 말고 **원래 키를 복구**한 뒤 `swift scripts/update_keys.swift check production`으로 공개 키와 일치하는지 확인하세요.

## 6. 첫 정식 릴리스

```sh
TYPINGPET_BUILD_CHANNEL=production ./scripts/build_app.sh
./scripts/notarize_release.sh
./scripts/deploy_update.sh production dist/TypingPet.app
```

자세한 업데이트 게시 절차는 [자동 업데이트](UPDATE.md)를 봅니다.

0.12.0 이하에는 업데이터가 없으므로 0.13.0은 사용자가 직접 설치해야 합니다.
ad-hoc으로 서명한 0.13.0 이후 빌드는 Ed25519 서명만 확인하고 첫 Developer ID 빌드까지 자동으로 업데이트할 수 있습니다.
ad-hoc 빌드는 업데이트할 때마다 입력 모니터링 권한을 다시 허용해야 하고, 첫 Developer ID 빌드로 바뀔 때도 한 번 다시 허용해야 합니다.
그 뒤 같은 Team ID로 서명한 업데이트는 권한을 유지합니다.
