export type { Locale } from './localization';
export const content = {
  ko: {
    title: 'Typing Pet — 타이핑에 작은 즐거움을, Mac에 작은 친구를.',
    description: '키를 누르면 반응하는 나만의 Mac 데스크톱 펫. 이미지 커스터마이징, 할 일과 집중 타이머까지. Apple Silicon · macOS 13 이상.',
    skip: '본문으로 건너뛰기', nav: ['기능', '설치하기', '패치 노트'],
    heroLabel: "키 입력에 반응하는 Mac 데스크톱 펫", hero1: '타닥타닥.', hero2: '혼자여도,', hero3: '같이 하는 기분.',
    heroBody: "키를 누를 때마다 꼬물꼬물. 원하는 이미지로 펫을 꾸미고, 옆에 할 일과 타이머를 띄워 두세요.",
    githubDownload: 'GitHub에서 다운로드', recommended: '추천', directDownload: '서버에서 직접 다운로드',
    installBrew: 'Homebrew로 설치', requirements: 'Apple Silicon · macOS 13 이상', signed: 'Apple 서명 및 공증 완료',
    demoTitle: "키 입력 반응 미리 보기", demoBubble: '오늘도 같이 해볼까?', demoTask: '한 가지에 집중하기', demoHint: '여기를 누르거나 아래에 타이핑해 보세요', demoPlaceholder: '안녕, 작은 친구!', demoLabel: '펫 반응 체험용 입력창', demoCaption: '웹 데모 · 입력은 저장하거나 전송하지 않아요', demoKey: '펫 반응 체험',
    strip: ['계정 없이 가볍게', '내 이미지로 자유롭게', 'Mac에서 네이티브로'],
    featureLabel: "주요 기능", featureTitle: '작은 펫 하나로,\n책상이 조금 달라져요.',
    features: [
      [
        "키 입력 반응",
        "키를 누르면 펫의 이미지가 바뀌고 통통 튀어요. 특정 키나 단축키에 표시할 이미지를 따로 지정할 수 있어요."
      ],
      [
        "내 이미지로 꾸미기",
        "대기 이미지와 반응 이미지를 직접 고르세요. 이미지 세트를 여러 개 만들어 갤러리에서 바꿔 쓸 수 있어요."
      ],
      [
        "할 일과 집중 타이머",
        "펫 옆에 할 일 목록과 타이머를 띄워 두세요. 카운트다운·카운트업과 간략 목록을 지원해요."
      ],
      [
        "크기와 표시 설정",
        "펫을 드래그해 옮기고 크기와 불투명도를 조절하세요. 다른 창 위에 표시하거나, 잠근 위치에서 마우스 포인터를 피하게 할 수 있어요."
      ]
    ],
    focusLabel: "할 일과 타이머", focusTitle: "펫 옆에 할 일을 적고,\n타이머를 켜세요.", focusBody: "할 일 목록을 펫 옆에 띄우고, 타이머로 작업 시간을 재세요. 공간을 적게 쓰고 싶다면 간략 목록으로 바꿀 수 있어요.",
    screenshotAlt: '할 일 두 개와 실행 중인 집중 타이머가 표시된 Typing Pet 간략 목록', screenshotCaption: '실제 앱 화면 · 예시 할 일로 촬영', focusTags: ['할 일 목록', '집중 타이머', 'Mac에만 저장'],
    installLabel: "설치 방법", installTitle: "Typing Pet 설치하기", installBody: "파일 다운로드와 Homebrew 중 원하는 방법을 고르세요.", zipTab: 'ZIP 다운로드', brewTab: 'Homebrew',
    dmgDownload: 'DMG 다운로드', dmgTab: 'DMG 다운로드', dmgTitle: 'DMG로 설치', dmgSteps: ['DMG를 내려받아 두 번 눌러 열어요.', 'TypingPet 앱을 옆의 Applications 폴더로 드래그하세요.', '디스크 이미지를 추출하고 응용 프로그램 폴더에서 앱을 열어요.'],
    zipTitle: "ZIP으로 설치", zipSteps: ['ZIP을 내려받아 압축을 풀어요.', 'TypingPet.app을 응용 프로그램 폴더로 옮겨요.', '앱을 열고 입력 모니터링 안내를 따라가세요.'],
    checksum: 'SHA-256 체크섬', releasePage: 'GitHub 릴리스 보기', brewTitle: "Homebrew로 설치", brewBody: 'Homebrew가 설치된 Mac에서 아래 명령을 실행하세요.', brewAfter: '설치 후 응용 프로그램에서 TypingPet을 실행하세요. 앱 내 자동 업데이트를 지원합니다.', brewUpdate: 'Homebrew로 직접 업데이트', copy: '명령 복사', copied: '복사했어요!', copyError: '명령을 선택해 직접 복사해 주세요.',
    permission: '첫 실행에는 입력 모니터링 권한이 필요해요. 앱 안에서 먼저 반응을 체험한 뒤, 안내에 따라 설정할 수 있어요.',
    faqTitle: '궁금한 점, 미리 답해요.', faqs: [
      ['제가 입력하는 내용을 읽나요?', '일반 입력 문자는 읽거나 저장하지 않습니다. 반응을 위한 키 이벤트를 감지하며, 키별 반응에는 직접 등록한 물리 키 코드와 보조 키 조합만 로컬에 저장합니다.'],
      ['할 일과 집중 기록은 어디에 저장되나요?', '이 Mac에만 저장됩니다. 계정이나 동기화는 없고, 할 일 기록을 서버에 올리지 않습니다. 앱의 네트워크 통신은 업데이트 확인과 다운로드에 사용됩니다.'],
      ['Intel Mac이나 Windows에서도 쓸 수 있나요?', '이 앱은 Apple Silicon Mac과 macOS 13 이상을 지원합니다. Windows용 프로젝트는 아래의 영감을 받은 프로젝트 링크에서 만나 보세요.'],
      ['오래된 버전에서 자동 업데이트가 안 돼요.', 'v0.14.1 이하에서는 최신 ZIP을 한 번 직접 설치해 주세요. v0.14.2 이후 버전은 앱 내 자동 업데이트를 지원합니다.']
    ],
    notesLabel: "업데이트", notesTitle: "업데이트 내역", notesBody: "버전별 변경 사항을 확인하세요.", allNotes: '모든 패치 노트 보기', latest: '최신 버전', prerelease: '프리릴리스', notesPageTitle: "업데이트 내역", notesPageBody: "Typing Pet의 버전별 변경 사항입니다.", back: '처음으로',
    creditLabel: "프로젝트 소개", creditTitle: "개발자와 원본 프로젝트", creditBody: 'Windows용 Typing Pet에서 영감을 받아 macOS용으로 새로 구현한 비공식 프로젝트입니다. 원본의 소스 코드와 이미지 자산은 포함하지 않습니다.', inspiration: '영감을 받은 프로젝트', maker: '만든 사람', contact: '문의하기', source: '소스 코드', license: '소스 MIT · 기본 이미지 CC0', footer: '당신의 타이핑에, 작은 즐거움을.',
    menuLabel: '주요 메뉴', languageLabel: '언어 선택',
    installMethod: '설치 방법', homeLabel: 'Typing Pet 홈', terminal: '터미널',
  },
  en: {
    title: 'Typing Pet — A little joy for every keystroke. A little friend for your Mac.',
    description: 'A native Mac desktop pet that reacts to your keystrokes. Make it yours with custom images, Todos, and a focus timer. Apple Silicon · macOS 13 or later.',
    skip: 'Skip to content', nav: ['Features', 'Install', 'Changelog'],
    heroLabel: "A MAC DESKTOP PET THAT REACTS AS YOU TYPE", hero1: 'Tap, tap.', hero2: 'A little company.', hero3: 'A lot more joy.',
    heroBody: "Watch your pet react as you type. Choose your own images and keep a Todo list and timer beside it.",
    githubDownload: 'Download from GitHub', recommended: 'Recommended', directDownload: 'Download from our server',
    installBrew: 'Install with Homebrew', requirements: 'Apple Silicon · macOS 13+', signed: 'Apple-signed & notarized',
    demoTitle: "Typing preview", demoBubble: 'Let’s do a little good today.', demoTask: 'One thing at a time', demoHint: 'Tap here or type in the box below', demoPlaceholder: 'Hello, little friend!', demoLabel: 'Type here to try the pet’s reactions', demoCaption: 'Web demo · nothing you type is stored or sent', demoKey: 'Try a pet reaction',
    strip: ['No account needed', 'Your images, your personality', 'Made natively for Mac'],
    featureLabel: "FEATURES", featureTitle: 'One little pet.\nA happier desktop.',
    features: [
      [
        "Reacts to your keyboard",
        "Your pet changes images and bounces as you type. Assign separate images to specific keys and shortcuts."
      ],
      [
        "Use your own images",
        "Choose idle and reaction images, save multiple image sets, and switch between them in the gallery."
      ],
      [
        "Todos and a focus timer",
        "Keep your Todo list and timer beside your pet. Use countdown or count-up timing, or switch to a compact list."
      ],
      [
        "Adjust the display",
        "Move your pet, resize it, and adjust its opacity. Keep it above other windows, or lock its position and let it move aside for your pointer."
      ]
    ],
    focusLabel: "TODOS AND TIMER", focusTitle: "Keep your tasks\nbeside your pet.", focusBody: "Write down a task and use the timer to track time spent on it. Switch to the compact list when you need more room.",
    screenshotAlt: 'Actual Typing Pet compact Todo list with two sample tasks and a running focus timer; the screenshot is in Korean', screenshotCaption: 'Actual app · sample tasks · shown in Korean', focusTags: ['Todo list', 'Focus timer', 'Stored on your Mac'],
    installLabel: "INSTALLATION", installTitle: "Install Typing Pet", installBody: "Download the app or install with Homebrew.", zipTab: 'Download ZIP', brewTab: 'Homebrew',
    dmgDownload: 'Download DMG', dmgTab: 'Download DMG', dmgTitle: 'Install from the DMG', dmgSteps: ['Download the DMG and double-click to open it.', 'Drag TypingPet into the Applications folder beside it.', 'Eject the disk image and open the app from Applications.'],
    zipTitle: "Install from the ZIP", zipSteps: ['Download the ZIP and unzip it.', 'Move TypingPet.app into Applications.', 'Open the app and follow the Input Monitoring guide.'],
    checksum: 'SHA-256 checksum', releasePage: 'View GitHub release', brewTitle: "Install with Homebrew", brewBody: 'Run these commands on a Mac with Homebrew installed.', brewAfter: 'Then open TypingPet from Applications. In-app automatic updates are supported.', brewUpdate: 'Update manually with Homebrew', copy: 'Copy commands', copied: 'Copied!', copyError: 'Please select and copy the commands manually.',
    permission: 'Typing Pet needs Input Monitoring permission to react across apps. Try the reactions in the app first, then follow the built-in setup guide.',
    faqTitle: 'A few things you might wonder.', faqs: [
      ['Does it read what I type?', 'It does not read or store normal input characters. It detects key events for reactions. Custom key reactions store only the physical key codes and modifier combinations you explicitly register, locally.'],
      ['Where do my Todos and focus records go?', 'They stay on this Mac. There is no account or sync, and Todo records are never uploaded. The app uses the network to check for and download updates.'],
      ['Does it work on Intel Macs or Windows?', 'This app supports Apple Silicon Macs running macOS 13 or later. For Windows, visit the project that inspired it, linked below.'],
      ['My older version will not update automatically.', 'If you have v0.14.1 or earlier, install the latest ZIP manually once. Versions from v0.14.2 onward support in-app automatic updates.']
    ],
    notesLabel: "UPDATES", notesTitle: "Release notes", notesBody: "See what changed in each version.", allNotes: 'Read all release notes', latest: 'Latest version', prerelease: 'Prerelease', notesPageTitle: "Release notes", notesPageBody: "Changes in each version of Typing Pet.", back: 'Back home',
    creditLabel: "ABOUT", creditTitle: "The developer and the original project", creditBody: 'An unofficial project built anew for macOS, inspired by Typing Pet for Windows. It does not include the original project’s source code or image assets.', inspiration: 'Inspired by', maker: 'Made by', contact: 'Get in touch', source: 'Source code', license: 'MIT source · CC0 default images', footer: 'A little joy for every keystroke.',
    menuLabel: 'Main navigation', languageLabel: 'Choose language',
    installMethod: 'Installation method', homeLabel: 'Typing Pet home', terminal: 'Terminal',
  },
  ja: {
    title: 'Typing Pet — タイピングに小さな楽しさを。Macに小さな友だちを。',
    description: 'キー入力に反応する、自分だけのMacデスクトップペット。画像のカスタマイズ、タスク、集中タイマーも。Apple Silicon · macOS 13以降。',
    skip: '本文へスキップ', nav: ['機能', 'インストール', '更新履歴'],
    heroLabel: "キー入力に反応するMac用デスクトップペット", hero1: 'カタカタ。', hero2: 'ひとりの時間に、', hero3: '小さな相棒。',
    heroBody: "キーを押すとペットが反応します。好きな画像に着せ替えて、隣にタスクリストやタイマーを表示できます。",
    githubDownload: 'GitHubからダウンロード', recommended: 'おすすめ', directDownload: 'サーバーから直接ダウンロード',
    installBrew: 'Homebrewでインストール', requirements: 'Apple Silicon · macOS 13以降', signed: 'Appleの署名・公証済み',
    demoTitle: "キー入力のプレビュー", demoBubble: '今日も一緒にやってみよう。', demoTask: 'ひとつのことに集中', demoHint: 'ここを押すか、下の欄で入力してみてください', demoPlaceholder: 'こんにちは、小さな友だち！', demoLabel: 'ペットの反応を試す入力欄', demoCaption: 'Webデモ · 入力は保存・送信しません', demoKey: 'ペットの反応を試す',
    strip: ['アカウント不要', '好きな画像で自由に', 'Macのネイティブアプリ'],
    featureLabel: "主な機能", featureTitle: '小さなペットで、\nデスクトップに楽しさを。',
    features: [
      [
        "キー入力に反応",
        "キーを押すとペットの画像が変わり、跳ねます。特定のキーやショートカットに画像を割り当てることもできます。"
      ],
      [
        "好きな画像を使う",
        "待機画像と反応画像を選び、画像セットとして保存できます。複数のセットをギャラリーで切り替えられます。"
      ],
      [
        "タスクと集中タイマー",
        "ペットの隣にタスクリストとタイマーを表示できます。カウントダウン・カウントアップやコンパクトなリストに対応しています。"
      ],
      [
        "表示を調整",
        "ドラッグで移動し、大きさや不透明度を調整できます。ほかのウインドウの手前に表示したり、位置を固定してポインタを避けるようにしたりできます。"
      ]
    ],
    focusLabel: "タスクとタイマー", focusTitle: "ペットの隣で、\nタスクと時間を管理。", focusBody: "タスクを書き留めて、タイマーで作業時間を計測できます。表示を小さくしたいときは、コンパクト表示に切り替えられます。",
    screenshotAlt: '2件のサンプルタスクと実行中の集中タイマーを表示したTyping Petのコンパクトリスト。画面は韓国語です', screenshotCaption: '実際のアプリ · サンプルタスク · 韓国語表示', focusTags: ['タスクリスト', '集中タイマー', 'Mac内に保存'],
    installLabel: "インストール方法", installTitle: "Typing Petをインストール", installBody: "ファイルをダウンロードするか、Homebrewでインストールできます。", zipTab: 'ZIPをダウンロード', brewTab: 'Homebrew',
    dmgDownload: 'DMGをダウンロード', dmgTab: 'DMGをダウンロード', dmgTitle: 'DMGからインストール', dmgSteps: ['DMGをダウンロードし、ダブルクリックで開きます。', 'TypingPetを隣のApplicationsフォルダにドラッグします。', 'ディスクイメージを取り出し、アプリケーションからアプリを開きます。'],
    zipTitle: "ZIPからインストール", zipSteps: ['ZIPをダウンロードして展開します。', 'TypingPet.appをアプリケーションフォルダに移動します。', 'アプリを開き、入力監視のガイドに従ってください。'],
    checksum: 'SHA-256チェックサム', releasePage: 'GitHubリリースを見る', brewTitle: "Homebrewでインストール", brewBody: 'HomebrewをインストールしたMacで、次のコマンドを実行してください。', brewAfter: 'インストール後、アプリケーションフォルダからTypingPetを開いてください。アプリ内の自動アップデートに対応しています。', brewUpdate: 'Homebrewで手動アップデート', copy: 'コマンドをコピー', copied: 'コピーしました！', copyError: 'コマンドを選択して手動でコピーしてください。',
    permission: 'ほかのアプリの使用中に反応するには、入力監視の許可が必要です。まずアプリ内で反応を試し、その後ガイドに沿って設定できます。',
    faqTitle: '気になることに、お答えします。', faqs: [
      ['入力した内容を読み取りますか？', '通常の入力文字を読み取ったり、保存したりしません。反応のためにキーイベントを検出します。キーごとの反応には、自分で登録した物理キーコードと修飾キーの組み合わせだけをローカルに保存します。'],
      ['タスクや集中の記録はどこに保存されますか？', 'このMac内に保存します。アカウントや同期機能はなく、タスクの記録をアップロードしません。ネットワークはアップデートの確認とダウンロードに使用します。'],
      ['Intel MacやWindowsでも使えますか？', 'Apple Silicon搭載MacとmacOS 13以降に対応しています。Windows向けには、下にリンクした着想元のプロジェクトをご覧ください。'],
      ['古いバージョンから自動アップデートできません。', 'v0.14.1以前をお使いの場合は、一度だけ最新ZIPを手動でインストールしてください。v0.14.2以降はアプリ内の自動アップデートに対応しています。']
    ],
    notesLabel: "アップデート", notesTitle: "更新履歴", notesBody: "バージョンごとの変更点を確認できます。", allNotes: 'すべての更新履歴を見る', latest: '最新バージョン', prerelease: 'プレリリース', notesPageTitle: "更新履歴", notesPageBody: "Typing Petの各バージョンの変更点です。", back: 'ホームへ戻る',
    creditLabel: "プロジェクトについて", creditTitle: "開発者と元のプロジェクト", creditBody: 'Windows向けTyping Petに着想を得て、macOS向けに新たに実装した非公式プロジェクトです。元のソースコードや画像素材は含みません。', inspiration: '着想元のプロジェクト', maker: '制作者', contact: 'お問い合わせ', source: 'ソースコード', license: 'ソース MIT · 標準画像 CC0', footer: 'タイピングに、小さな楽しさを。',
    menuLabel: 'メインメニュー', languageLabel: '言語を選択', installMethod: 'インストール方法', homeLabel: 'Typing Pet ホーム', terminal: 'ターミナル',
  },
  'zh-Hans': {
    title: 'Typing Pet — 为每次敲键添点乐趣，为 Mac 添个小伙伴。',
    description: '随按键作出反应的 Mac 原生桌面宠物。自定义图片、待办事项与专注计时器，让它更懂你。Apple Silicon · macOS 13 或更高版本。',
    skip: '跳转到正文', nav: ['功能', '安装', '更新日志'],
    heroLabel: "随按键作出反应的 Mac 桌面宠物", hero1: '哒哒哒。', hero2: '独处的时光，', hero3: '也有小小陪伴。',
    heroBody: "按下键盘，宠物就会作出反应。你可以换上喜欢的图片，在它旁边显示待办列表和计时器。",
    githubDownload: '从 GitHub 下载', recommended: '推荐', directDownload: '从服务器直接下载',
    installBrew: '通过 Homebrew 安装', requirements: 'Apple Silicon · macOS 13 或更高版本', signed: '已通过 Apple 签名与公证',
    demoTitle: "按键反应预览", demoBubble: '今天也一起加油吧！', demoTask: '一次专注一件事', demoHint: '点点这里，或在下方输入试试', demoPlaceholder: '你好，小伙伴！', demoLabel: '输入文字，体验宠物反应', demoCaption: '网页演示 · 不保存或发送输入内容', demoKey: '体验宠物反应',
    strip: ['无需账号', '随心使用自己的图片', '为 Mac 原生打造'],
    featureLabel: "主要功能", featureTitle: '一只小宠物，\n让桌面多点乐趣。',
    features: [
      [
        "响应键盘输入",
        "打字时，宠物会切换图片并跳动。也可以为特定按键和快捷键指定图片。"
      ],
      [
        "使用自己的图片",
        "选择待机图片和反应图片，保存为图片集。在图库中可以切换多个图片集。"
      ],
      [
        "待办和专注计时",
        "在宠物旁边显示待办列表和计时器，支持倒计时、正计时和精简列表。"
      ],
      [
        "调整显示方式",
        "拖动宠物来移动它，并调整大小和不透明度。可以置于其他窗口上方，也可以锁定位置并让它避开鼠标指针。"
      ]
    ],
    focusLabel: "待办和计时器", focusTitle: "在宠物旁边\n记下待办、开始计时。", focusBody: "记下要做的事，用计时器记录任务用时。想少占一些空间时，可以切换到精简列表。",
    screenshotAlt: 'Typing Pet 紧凑待办列表，显示两个示例任务和正在运行的专注计时器；截图为韩语', screenshotCaption: '应用实拍 · 示例任务 · 韩语界面', focusTags: ['待办列表', '专注计时器', '仅保存在 Mac 上'],
    installLabel: "安装方法", installTitle: "安装 Typing Pet", installBody: "下载安装文件，或使用 Homebrew 安装。", zipTab: '下载 ZIP', brewTab: 'Homebrew',
    dmgDownload: '下载 DMG', dmgTab: '下载 DMG', dmgTitle: '通过 DMG 安装', dmgSteps: ['下载 DMG，双击打开。', '将 TypingPet 拖到旁边的 Applications 文件夹。', '推出磁盘映像，然后从“应用程序”打开应用。'],
    zipTitle: "通过 ZIP 文件安装", zipSteps: ['下载 ZIP 并解压。', '将 TypingPet.app 移到“应用程序”文件夹。', '打开应用，按照输入监控指南完成设置。'],
    checksum: 'SHA-256 校验和', releasePage: '查看 GitHub 发行版', brewTitle: "使用 Homebrew 安装", brewBody: '在已安装 Homebrew 的 Mac 上运行以下命令。', brewAfter: '安装后，从“应用程序”打开 TypingPet。支持应用内自动更新。', brewUpdate: '使用 Homebrew 手动更新', copy: '复制命令', copied: '已复制！', copyError: '请选中命令并手动复制。',
    permission: '要在其他应用中响应按键，Typing Pet 需要输入监控权限。可以先在应用内体验反应，再按照指南进行设置。',
    faqTitle: '你可能想了解这些。', faqs: [
      ['它会读取我输入的内容吗？', '不会读取或保存普通输入字符。它检测按键事件来作出反应。自定义按键反应仅在本机保存你主动注册的物理键码和修饰键组合。'],
      ['待办事项和专注记录存在哪里？', '只保存在这台 Mac 上。无需账号，没有同步，也不会上传待办记录。应用仅使用网络检查和下载更新。'],
      ['支持 Intel Mac 或 Windows 吗？', '此应用支持搭载 Apple Silicon、运行 macOS 13 或更高版本的 Mac。Windows 用户可访问下方链接的灵感来源项目。'],
      ['旧版本无法自动更新。', '如果你使用 v0.14.1 或更早版本，请手动安装一次最新 ZIP。v0.14.2 及之后的版本支持应用内自动更新。']
    ],
    notesLabel: "更新", notesTitle: "更新日志", notesBody: "查看各版本的改动。", allNotes: '查看全部更新日志', latest: '最新版本', prerelease: '预发布版', notesPageTitle: "更新日志", notesPageBody: "Typing Pet 各版本的改动记录。", back: '返回首页',
    creditLabel: "关于项目", creditTitle: "开发者和原项目", creditBody: '受 Windows 版 Typing Pet 启发，为 macOS 重新实现的非官方项目。不包含原项目的源代码或图片素材。', inspiration: '灵感来源', maker: '作者', contact: '联系我们', source: '源代码', license: '源码 MIT · 默认图片 CC0', footer: '为每次敲键，添一点乐趣。',
    menuLabel: '主导航', languageLabel: '选择语言', installMethod: '安装方式', homeLabel: 'Typing Pet 首页', terminal: '终端',
  },
  'zh-Hant': {
    title: 'Typing Pet — 為每次敲鍵添點樂趣，為 Mac 添個小夥伴。',
    description: '隨按鍵作出反應的 Mac 原生桌面寵物。自訂圖片、待辦事項與專注計時器，讓它更懂你。Apple Silicon · macOS 13 或以上版本。',
    skip: '跳至主要內容', nav: ['功能', '安裝', '更新紀錄'],
    heroLabel: "隨按鍵作出反應的 Mac 桌面寵物", hero1: '答答答。', hero2: '獨處的時光，', hero3: '也有小小陪伴。',
    heroBody: "按下鍵盤，寵物就會作出反應。你可以換上喜歡的圖片，在牠旁邊顯示待辦清單和計時器。",
    githubDownload: '從 GitHub 下載', recommended: '推薦', directDownload: '從伺服器直接下載',
    installBrew: '透過 Homebrew 安裝', requirements: 'Apple Silicon · macOS 13 或以上版本', signed: '已通過 Apple 簽署與公證',
    demoTitle: "按鍵反應預覽", demoBubble: '今天也一起加油吧！', demoTask: '一次專注一件事', demoHint: '點點這裡，或在下方輸入試試', demoPlaceholder: '你好，小夥伴！', demoLabel: '輸入文字，體驗寵物反應', demoCaption: '網頁示範 · 不儲存或傳送輸入內容', demoKey: '體驗寵物反應',
    strip: ['不需帳號', '隨心使用自己的圖片', '專為 Mac 原生打造'],
    featureLabel: "主要功能", featureTitle: '一隻小寵物，\n讓桌面多點樂趣。',
    features: [
      [
        "回應鍵盤輸入",
        "打字時，寵物會切換圖片並跳動。也可以為特定按鍵和快捷鍵指定圖片。"
      ],
      [
        "使用自己的圖片",
        "選擇待機圖片和反應圖片，儲存為圖片集。在圖庫中可以切換多個圖片集。"
      ],
      [
        "待辦與專注計時",
        "在寵物旁邊顯示待辦清單和計時器，支援倒數計時、正向計時和精簡清單。"
      ],
      [
        "調整顯示方式",
        "拖曳寵物來移動牠，並調整大小和不透明度。可以置於其他視窗上方，也可以鎖定位置並讓牠避開滑鼠指標。"
      ]
    ],
    focusLabel: "待辦與計時器", focusTitle: "在寵物旁邊\n記下待辦、開始計時。", focusBody: "記下要做的事，用計時器記錄任務所花的時間。想少占一些空間時，可以切換到精簡清單。",
    screenshotAlt: 'Typing Pet 精簡待辦列表，顯示兩個範例任務和正在執行的專注計時器；截圖為韓文', screenshotCaption: 'App 實拍 · 範例任務 · 韓文介面', focusTags: ['待辦列表', '專注計時器', '僅儲存在 Mac 上'],
    installLabel: "安裝方式", installTitle: "安裝 Typing Pet", installBody: "下載安裝檔案，或使用 Homebrew 安裝。", zipTab: '下載 ZIP', brewTab: 'Homebrew',
    dmgDownload: '下載 DMG', dmgTab: '下載 DMG', dmgTitle: '透過 DMG 安裝', dmgSteps: ['下載 DMG，按兩下開啟。', '將 TypingPet 拖到旁邊的 Applications 檔案夾。', '退出磁碟映像檔，然後從「應用程式」開啟 App。'],
    zipTitle: "透過 ZIP 檔案安裝", zipSteps: ['下載 ZIP 並解壓縮。', '將 TypingPet.app 移到「應用程式」檔案夾。', '開啟 App，按照輸入監控指南完成設定。'],
    checksum: 'SHA-256 校驗碼', releasePage: '查看 GitHub 發行版本', brewTitle: "使用 Homebrew 安裝", brewBody: '在已安裝 Homebrew 的 Mac 上執行以下指令。', brewAfter: '安裝後，從「應用程式」開啟 TypingPet。支援 App 內自動更新。', brewUpdate: '使用 Homebrew 手動更新', copy: '拷貝指令', copied: '已拷貝！', copyError: '請選取指令並手動拷貝。',
    permission: '若要在其他 App 中回應按鍵，Typing Pet 需要輸入監控權限。可以先在 App 內體驗反應，再按照指南進行設定。',
    faqTitle: '你可能想了解這些。', faqs: [
      ['牠會讀取我輸入的內容嗎？', '不會讀取或儲存一般輸入字元。它偵測按鍵事件來作出反應。自訂按鍵反應僅在本機儲存你主動登錄的實體鍵碼和修飾鍵組合。'],
      ['待辦事項和專注紀錄存在哪裡？', '僅儲存在這台 Mac 上。不需帳號，沒有同步，也不會上傳待辦紀錄。App 僅使用網路檢查和下載更新。'],
      ['支援 Intel Mac 或 Windows 嗎？', '此 App 支援搭載 Apple Silicon、執行 macOS 13 或以上版本的 Mac。Windows 使用者可造訪下方連結的靈感來源專案。'],
      ['舊版本無法自動更新。', '若使用 v0.14.1 或更早版本，請手動安裝一次最新 ZIP。v0.14.2 及之後的版本支援 App 內自動更新。']
    ],
    notesLabel: "更新", notesTitle: "更新紀錄", notesBody: "查看各版本的變更。", allNotes: '查看全部更新紀錄', latest: '最新版本', prerelease: '預先發行版', notesPageTitle: "更新紀錄", notesPageBody: "Typing Pet 各版本的變更紀錄。", back: '返回首頁',
    creditLabel: "關於專案", creditTitle: "開發者與原專案", creditBody: '受 Windows 版 Typing Pet 啟發，為 macOS 重新實作的非官方專案。不包含原專案的原始碼或圖片素材。', inspiration: '靈感來源', maker: '作者', contact: '聯絡我們', source: '原始碼', license: '原始碼 MIT · 預設圖片 CC0', footer: '為每次敲鍵，添一點樂趣。',
    menuLabel: '主要導覽', languageLabel: '選擇語言', installMethod: '安裝方式', homeLabel: 'Typing Pet 首頁', terminal: '終端機',
  },
};
