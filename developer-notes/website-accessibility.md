# 홈페이지 Base UI 컴포넌트 점검

2026-10-24~25, 설치된 `@base-ui/react` 1.9.0과 같은 버전의 공식 문서·예제를 확인했습니다.
범위는 다섯 언어의 홈·패치 노트 페이지에 있는 선택 메뉴, 설치 탭, FAQ, 뉴스레터와 방문 통계 설정입니다.

## 사례와 반영 내용

| 대상 | 이전 구현과 확인한 문제 | 반영 |
| --- | --- | --- |
| 페이지 언어 | `details` 안의 일반 링크 목록. 메뉴 방향키 탐색·문자 검색·Escape 닫기·포커스 복귀가 제공되지 않음 | `Menu.Trigger → Portal → Positioner → Popup → LinkItem`. 언어별 링크와 현재 언어 표시를 유지하고 페이지·쿼리·앵커와 언어 저장을 보존 |
| 화면 모드 | `details`와 네이티브 라디오. 선택할 때 직접 닫고 포커스를 돌리는 코드, 문서 전체의 포인터 이벤트 처리 | `Menu.RadioGroup / RadioItem / RadioItemIndicator`. 키보드 이동과 선택을 구분하고 닫기·포커스를 라이브러리에 위임. 기존 시스템 설정·저장·탭 동기화 컨트롤러 유지 |
| 뉴스레터 수신 언어 | 사이트의 다른 선택 UI와 다른 네이티브 `select` | `Select.Label / Trigger / Value / Portal / Positioner / Popup / List / Item`. 레이블, 선택 표시, 문자 검색, 키보드 탐색과 폼 값 연결 |
| 뉴스레터 입력·동의 | 네이티브 검증 팝업과 기본 체크박스. 필드에 연결된 자체 오류 안내 없음 | `Form / Field / Input / Checkbox`. 잘못된 필드로 포커스 이동, 오류의 `aria-describedby` 연결, 필수 동의 검사. 성공 시 입력·체크·검증 상태를 함께 초기화하고 결과로 포커스 이동 |
| 개인정보·Homebrew 안내 | 개별 `details/summary` | 공통 `Collapsible.Trigger / Panel` 컴포넌트로 펼침 상태와 제어 관계 통일 |
| 방문 통계 | `aria-pressed` 버튼의 이름이 켜기/끄기로 계속 바뀜 | 고정 레이블의 `Switch`와 켜짐 상태. 저장 및 DNT/GPC 처리 코드 유지 |
| 본문 바로가기·체험 입력 | 바로가기 대상이 명시적으로 포커스를 받을 수 없음, 체험 입력은 별도 네이티브 요소 | 본문에 `tabIndex=-1`, 체험 입력에 `Input` 적용 |

`details`, 네이티브 입력, 링크 자체가 접근성 오류라는 뜻은 아닙니다. 해당 UI의 역할에 맞는 동작과 사이트의 일관성을 기준으로 변경했습니다.
일반 페이지 이동·파일 다운로드는 실제 `<a>` 링크를 유지합니다.

팝업은 포털과 충돌 방지 여백을 사용합니다. 키보드 강조에는 `data-highlighted`를 사용하고, 체크박스·스위치·탭에는 밝은/어두운 화면 모두 보이는 포커스 표시를 적용했습니다.
문서 이벤트나 CSS의 `:hover`만으로 메뉴를 열고 닫는 코드는 제거했습니다.

## 공식 사례

- [Menu: 페이지 이동과 라디오 항목](https://base-ui.com/react/components/menu): 언어 이동은 `LinkItem`, 설정 선택은 `RadioGroup`으로 구성했습니다.
- [Select: 구성과 레이블](https://base-ui.com/react/components/select): `Select.Label`과 실제 트리거를 연결하고 선택값·항목을 분리했습니다.
- [Forms: 레이블, 검증과 오류](https://base-ui.com/react/handbook/forms), [Field](https://base-ui.com/react/components/field), [Checkbox](https://base-ui.com/react/components/checkbox): 폼을 제출하기 전 필수 입력과 동의를 검사하고 오류를 해당 제어에 연결했습니다.
- [Collapsible](https://base-ui.com/react/components/collapsible), [Switch](https://base-ui.com/react/components/switch): 펼침과 즉시 적용되는 설정을 각각의 역할에 맞게 구성했습니다.
- [Tabs](https://base-ui.com/react/components/tabs): 기본 수동 활성화 방식 유지. 방향키는 탭 포커스를 이동하고 Enter/Space가 패널을 전환합니다.
- [Accordion](https://base-ui.com/react/components/accordion): 1.9.0은 APG 변경에 따라 `loopFocus`와 `orientation`의 포커스 제어를 폐기했습니다. FAQ는 기본 Tab 탐색과 Enter/Space 펼침을 유지합니다.

## 검증

실제 브라우저에서 키 입력과 접근성 트리/DOM을 확인했습니다.

- 언어: Tab 진입, Enter/방향키 열기, 방향키·End 이동, 문자 검색, Escape 및 Tab 닫기, 트리거/다음 제어로 포커스 이동.
- `/ko/changelog/?from=keyboard#newsletter`에서 키보드로 English를 선택했을 때 `/en/changelog/?from=keyboard#newsletter`로 이동.
- 화면 모드: Space/방향키 열기, 방향키 이동과 Enter 선택, 닫힌 뒤 트리거로 포커스 복귀, 새로고침 후 선택 유지.
- 수신 언어: 명명된 combobox, 방향키·Home·Enter 선택, 닫힌 뒤 트리거 복귀, 숨겨진 폼 값 일치.
- 빈 폼: 이메일로 포커스 이동, 이메일과 필수 동의의 오류 메시지 및 `aria-invalid` 상태.
- 동의: Space 선택과 Tab 이동. 폼 제출 전 필수 동의를 검사.
- 로컬 합성 API: 수신 언어 `ja`, 두 동의, 동의 문구 버전, 이름과 이메일의 요청 형식 확인. 성공 후 입력·체크·오류 초기화 및 결과 포커스 확인. 429 오류 후 입력 보존·오류 결과 포커스·재시도, 해지 경로 및 신청/해지 전환 시 이메일 보존 확인.
- 설치 탭: DMG 우선 유지, 방향키/End와 Enter로 ZIP·Homebrew 전환. FAQ와 두 안내 펼침의 Enter/Space 동작 확인.
- 방문 통계: Space 변경, 새로고침 후 선택 유지.
- 375px 화면에서 페이지의 가로 넘침과 Select 팝업 잘림 확인.
- 빌드: TypeScript, 기존 화면 모드 테스트, 분석 이벤트 허용 목록 검사, 다섯 언어의 정적 페이지 10개 검사.

합성 API는 `127.0.0.1`의 별도 테스트 서버에서만 동작하고 실제 뉴스레터 신청이나 이메일 발송을 수행하지 않습니다.
VoiceOver의 실제 음성 낭독은 이 점검에 포함하지 않았습니다.
