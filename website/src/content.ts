export type { Locale } from './localization';
export const content = {
  ko: {
    title: 'Typing Pet — 타이핑에 작은 즐거움을, Mac에 작은 친구를.',
    description: '키를 누르면 반응하는 나만의 Mac 데스크톱 펫입니다. 이미지와 할 일 목록을 자유롭게 꾸미고 집중 타이머도 사용할 수 있어요. Apple Silicon Mac에서 macOS 27 이상을 지원합니다.',
    skip: '본문으로 건너뛰기', nav: ['기능', '설치하기', '업데이트 내역', '소식 받기'],
    heroLabel: "", hero1: '언제까지나', hero2: '최애와 함께', hero3: '같이 하는 기분.',
    heroBody: "키를 누를 때마다 꼬물꼬물. 원하는 이미지로 펫을 꾸미고, 옆에 할 일과 타이머를 띄워 두세요.",
    githubDownload: 'GitHub에서 다운로드', recommended: '추천', directDownload: '서버에서 직접 다운로드',
    installBrew: 'Homebrew로 설치', requirements: 'macOS 27 이상 지원', updatedToday: '오늘 업데이트', signed: 'Apple 서명 및 공증 완료',
    demoTitle: "Typing Pet", demoBubble: '아무 키나 눌러 봐!', demoTask: '스크럼 작성하기', demoHint: '여기를 누르거나 아래에 타이핑해 보세요', demoPlaceholder: '안녕, 작은 친구!', demoLabel: '펫 반응 체험용 입력창', demoCaption: '키 입력은 반응에만 사용하며 저장하거나 전송하지 않아요', demoKey: '펫 반응 체험',
    strip: ['자유로운 커스텀', '귀여운 친구가 통통', '쉬운 이미지 팩 다운로드 (지원 예정)'],
    featureLabel: "주요 기능", featureTitle: '작은 펫 하나로,\n컴퓨터가 조금 달라져요.',
    features: [
      [
        "키 입력 반응",
        "키를 누르면 펫이나 최애의 이미지가 바뀌고 통통 튀어요. 특정 키나 단축키에 반응할 이미지를 자유롭게 지정할 수 있어요."
      ],
      [
        "내 이미지로 꾸미기",
        "대기 이미지와 반응 이미지를 직접 고르세요. 이미지 세트를 여러 개 만들어 갤러리에서 바꿔 쓸 수 있어요."
      ],
      [
        "할 일과 집중 타이머 (유료 기능)",
        "펫 옆에 할 일 목록과 타이머를 띄워 두세요. 카운트다운과 카운트업, 간략 목록을 지원해요."
      ],
      [
        "크기와 표시 설정",
        "펫을 자유롭게 드래그해 옮기고 크기와 불투명도를 조절하세요. 다른 창 위에 표시하거나, 잠근 위치에서 마우스 포인터를 피하게 할 수 있어요."
      ]
    ],
    focusLabel: "", focusTitle: "최애와 함께 집중해요.", focusBody: "",
    screenshotAlt: '할 일 두 개와 실행 중인 집중 타이머가 표시된 Typing Pet 간략 목록', screenshotCaption: '실제 앱 화면에서 예시 할 일로 촬영', focusTags: ['할 일 관리', '집중 타이머', '뽀모도로 타이머'],
    installLabel: "설치 방법", installTitle: "Typing Pet 설치하기", installBody: "", zipTab: 'ZIP 다운로드', brewTab: 'Homebrew',
    dmgDownload: 'DMG 다운로드', dmgTab: 'DMG 다운로드', dmgTitle: 'DMG로 설치 (권장)', dmgSteps: ['DMG를 내려받아 두 번 눌러 열어요.', 'TypingPet 앱을 옆의 Applications 폴더로 드래그하세요.', '디스크 이미지를 추출하고 응용 프로그램 폴더에서 앱을 열어요.'],
    zipTitle: "ZIP으로 설치", zipSteps: ['ZIP을 내려받아 압축을 풀어요.', 'TypingPet.app을 응용 프로그램 폴더로 옮겨요.', '앱을 열고 입력 모니터링 안내를 따라가세요.'],
    checksum: 'SHA-256', copyChecksum: '체크섬 복사', copyFailed: '복사 실패', releasePage: 'GitHub 릴리스 보기', brewTitle: "Homebrew로 설치", brewBody: 'Homebrew가 설치된 Mac에서 아래 명령을 실행하세요.', brewAfter: '설치 후 응용 프로그램에서 TypingPet을 실행하세요.', brewUpdate: 'Homebrew로 직접 업데이트', copy: '명령 복사', copied: '복사했어요!', copyError: '명령을 선택해 직접 복사해 주세요.',
    faqTitle: 'Q & A', faqs: [
      ['제가 입력하는 내용을 읽나요?', '일반 입력 문자는 읽거나 저장하지 않습니다. 반응을 위한 키 이벤트를 감지하며, 키별 반응에는 직접 등록한 물리 키 코드와 보조 키 조합만 로컬에 저장합니다.'],
      ['할 일과 집중 기록은 어디에 저장되나요?', '앞으로 코드를 입력해 이미지 팩을 다운로드하고, 기기 간 설정을 동기화하거나 백업하는 기능을 추가할 예정입니다.'],
      ['Intel Mac이나 Windows에서도 쓸 수 있나요?', '이 앱은 Apple Silicon Mac에서 macOS 27 이상을 지원합니다. Windows용 Typing Pet을 참고해 보세요.']
    ],
    faqWindowsLink: 'Windows용 Typing Pet',
    notesLabel: "업데이트", notesTitle: "업데이트 내역", notesBody: "디테일에 집착하는 중...", allNotes: '모든 업데이트 내역 보기', latest: '최신 버전', prerelease: '프리릴리스', notesPageTitle: "업데이트 내역", notesPageBody: "Typing Pet의 버전별 변경 사항입니다.", back: '처음으로',
    creditLabel: "프로젝트 소개", creditTitle: "만든 사람", creditBody: 'Windows용 Typing Pet에서 영감을 받아 macOS용으로 새로 구현한 프로젝트예요.', inspiration: '영감을 받은 원본 프로젝트', windowsVersion: 'Windows 버전 보기 (swoonqx/TypingPet)', maker: '만든 사람', makerDisplayName: '미엘', contact: '문의하기', source: '소스 코드', license: 'MIT 라이선스', footer: '언제까지나 최애와 함께 같이 하는 기분.',
    menuLabel: '주요 메뉴', languageLabel: '언어 선택',
    installMethod: '설치 방법', homeLabel: 'Typing Pet 홈', terminal: '터미널',
  },
  en: {
    title: 'Typing Pet — A little joy for every keystroke. A little friend for your Mac.',
    description: 'A native Mac desktop pet that reacts to your keystrokes. Customize its images, keep a Todo list, and use a focus timer. It supports Apple Silicon Macs running macOS 27 or later.',
    skip: 'Skip to content', nav: ['Features', 'Install', 'Changelog', 'Subscribe'],
    heroLabel: "", hero1: 'Always', hero2: 'with your favorite', hero3: 'by your side.',
    heroBody: "Watch your pet react as you type. Choose your own images and keep a Todo list and timer beside it.",
    githubDownload: 'Download from GitHub', recommended: 'Recommended', directDownload: 'Download from our server',
    installBrew: 'Install with Homebrew', requirements: 'Supports macOS 27 or later', updatedToday: 'Updated today', signed: 'Apple-signed & notarized',
    demoTitle: "Typing preview", demoBubble: 'Press any key!', demoTask: 'One thing at a time', demoHint: 'Tap here or type in the box below', demoPlaceholder: 'Hello, little friend!', demoLabel: 'Type here to try the pet’s reactions', demoCaption: 'Keystrokes only animate the pet. They are never stored or sent.', demoKey: 'Try a pet reaction',
    strip: ['Customize freely', 'A cute friend that bounces', 'Easy image pack downloads (planned)'],
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
    focusLabel: "", focusTitle: "Focus with your fave.", focusBody: "",
    screenshotAlt: 'Actual Typing Pet compact Todo list with two sample tasks and a running focus timer; the screenshot is in Korean', screenshotCaption: 'Actual app showing sample tasks in Korean', focusTags: ['Todo list', 'Focus timer', 'Pomodoro timer'],
    installLabel: "", installTitle: "Install Typing Pet", installBody: "", zipTab: 'Download ZIP', brewTab: 'Homebrew',
    dmgDownload: 'Download DMG', dmgTab: 'Download DMG', dmgTitle: 'Install from the DMG (recommended)', dmgSteps: ['Download the DMG and double-click to open it.', 'Drag TypingPet into the Applications folder beside it.', 'Eject the disk image and open the app from Applications.'],
    zipTitle: "Install from the ZIP", zipSteps: ['Download the ZIP and unzip it.', 'Move TypingPet.app into Applications.', 'Open the app and follow the Input Monitoring guide.'],
    checksum: 'SHA-256', copyChecksum: 'Copy checksum', copyFailed: 'Copy failed', releasePage: 'View GitHub release', brewTitle: "Install with Homebrew", brewBody: 'Run these commands on a Mac with Homebrew installed.', brewAfter: 'Then open TypingPet from Applications.', brewUpdate: 'Update manually with Homebrew', copy: 'Copy commands', copied: 'Copied!', copyError: 'Please select and copy the commands manually.',
    faqTitle: 'A few things you might wonder.', faqs: [
      ['Does it read what I type?', 'It does not read or store normal input characters. It detects key events for reactions. Custom key reactions store only the physical key codes and modifier combinations you explicitly register, locally.'],
      ['What’s coming next?', 'We plan to add code-based image pack downloads, along with settings sync and backups across devices.'],
      ['Does it work on Intel Macs or Windows?', 'This app supports Apple Silicon Macs running macOS 27 or later. For Windows, see the Typing Pet project linked below.']
    ],
    faqWindowsLink: 'Typing Pet for Windows',
    notesLabel: "UPDATES", notesTitle: "Release notes", notesBody: "Obsessing over the details...", allNotes: 'Read all release notes', latest: 'Latest version', prerelease: 'Prerelease', notesPageTitle: "Release notes", notesPageBody: "Changes in each version of Typing Pet.", back: 'Back home',
    creditLabel: "ABOUT", creditTitle: "The creator", creditBody: 'Inspired by Typing Pet for Windows, I built this project for macOS.\n\nI made it to use while I work.', inspiration: 'Inspired by the original project', windowsVersion: 'View the Windows version', maker: 'Made by', makerDisplayName: 'Miel', contact: 'Get in touch', source: 'Source code', license: 'MIT License', footer: 'Always by your favorite’s side.',
    menuLabel: 'Main navigation', languageLabel: 'Choose language',
    installMethod: 'Installation method', homeLabel: 'Typing Pet home', terminal: 'Terminal',
  },
  ja: {
    title: 'Typing Pet — タイピングに小さな楽しさを。Macに小さな友だちを。',
    description: 'キー入力に反応する、自分だけのMacデスクトップペットです。画像をカスタマイズし、タスクや集中タイマーも使えます。Apple Silicon搭載MacでmacOS 27以降に対応しています。',
    skip: '本文へスキップ', nav: ['機能', 'インストール', '更新履歴', 'お知らせ'],
    heroLabel: "", hero1: 'いつまでも', hero2: '推しと一緒に', hero3: '過ごす気分。',
    heroBody: "キーを押すとペットが反応します。好きな画像に着せ替えて、隣にタスクリストやタイマーを表示できます。",
    githubDownload: 'GitHubからダウンロード', recommended: 'おすすめ', directDownload: 'サーバーから直接ダウンロード',
    installBrew: 'Homebrewでインストール', requirements: 'macOS 27以降に対応', updatedToday: '今日更新', signed: 'Appleの署名と公証を完了しています',
    demoTitle: "キー入力のプレビュー", demoBubble: 'どれかキーを押してみて！', demoTask: 'ひとつのことに集中', demoHint: 'ここを押すか、下の欄で入力してみてください', demoPlaceholder: 'こんにちは、小さな友だち！', demoLabel: 'ペットの反応を試す入力欄', demoCaption: 'キー入力はペットの反応にのみ使い、保存も送信もしません。', demoKey: 'ペットの反応を試す',
    strip: ['自由にカスタマイズ', 'かわいい友達がぴょん', '画像パックを簡単にダウンロード（予定）'],
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
        "ペットの隣にタスクリストとタイマーを表示できます。カウントダウンとカウントアップ、コンパクトなリストに対応しています。"
      ],
      [
        "表示を調整",
        "ドラッグで移動し、大きさや不透明度を調整できます。ほかのウインドウの手前に表示したり、位置を固定してポインタを避けるようにしたりできます。"
      ]
    ],
    focusLabel: "", focusTitle: "推しと一緒に集中。", focusBody: "",
    screenshotAlt: '2件のサンプルタスクと実行中の集中タイマーを表示したTyping Petのコンパクトリスト。画面は韓国語です', screenshotCaption: '実際のアプリで韓国語のサンプルタスクを表示', focusTags: ['タスク管理', '集中タイマー', 'ポモドーロタイマー'],
    installLabel: "", installTitle: "Typing Petをインストール", installBody: "", zipTab: 'ZIPをダウンロード', brewTab: 'Homebrew',
    dmgDownload: 'DMGをダウンロード', dmgTab: 'DMGをダウンロード', dmgTitle: 'DMGからインストール（おすすめ）', dmgSteps: ['DMGをダウンロードし、ダブルクリックで開きます。', 'TypingPetを隣のApplicationsフォルダにドラッグします。', 'ディスクイメージを取り出し、アプリケーションからアプリを開きます。'],
    zipTitle: "ZIPからインストール", zipSteps: ['ZIPをダウンロードして展開します。', 'TypingPet.appをアプリケーションフォルダに移動します。', 'アプリを開き、入力監視のガイドに従ってください。'],
    checksum: 'SHA-256', copyChecksum: 'チェックサムをコピー', copyFailed: 'コピーできませんでした', releasePage: 'GitHubリリースを見る', brewTitle: "Homebrewでインストール", brewBody: 'HomebrewをインストールしたMacで、次のコマンドを実行してください。', brewAfter: 'インストール後、アプリケーションフォルダからTypingPetを開いてください。', brewUpdate: 'Homebrewで手動アップデート', copy: 'コマンドをコピー', copied: 'コピーしました！', copyError: 'コマンドを選択して手動でコピーしてください。',
    faqTitle: '気になることに、お答えします。', faqs: [
      ['入力した内容を読み取りますか？', '通常の入力文字を読み取ったり、保存したりしません。反応のためにキーイベントを検出します。キーごとの反応には、自分で登録した物理キーコードと修飾キーの組み合わせだけをローカルに保存します。'],
      ['今後どんな機能が追加されますか？', '今後、コードを入力して画像パックをダウンロードする機能と、デバイス間の設定同期・バックアップ機能を追加する予定です。'],
      ['Intel MacやWindowsでも使えますか？', 'Apple Silicon搭載MacでmacOS 27以降に対応しています。Windows版Typing Petもご覧ください。']
    ],
    faqWindowsLink: 'Windows版Typing Pet',
    notesLabel: "アップデート", notesTitle: "更新履歴", notesBody: "細部にこだわり中...", allNotes: 'すべての更新履歴を見る', latest: '最新バージョン', prerelease: 'プレリリース', notesPageTitle: "更新履歴", notesPageBody: "Typing Petの各バージョンの変更点です。", back: 'ホームへ戻る',
    creditLabel: "プロジェクトについて", creditTitle: "作った人", creditBody: 'Windows版Typing Petに着想を得て、macOS向けに新しく実装しました。\n\n仕事中に使うために作りました。', inspiration: '着想を得た元のプロジェクト', windowsVersion: 'Windows版を見る', maker: '制作者', makerDisplayName: 'ミエル', contact: 'お問い合わせ', source: 'ソースコード', license: 'MITライセンス', footer: 'いつまでも、推しと一緒に過ごす気分。',
    menuLabel: 'メインメニュー', languageLabel: '言語を選択', installMethod: 'インストール方法', homeLabel: 'Typing Pet ホーム', terminal: 'ターミナル',
  },
  'zh-Hans': {
    title: 'Typing Pet — 为每次敲键添点乐趣，为 Mac 添个小伙伴。',
    description: '一款会随按键作出反应的 Mac 原生桌面宠物。你可以自定义图片、管理待办事项并使用专注计时器。支持 Apple Silicon Mac 和 macOS 27 或更高版本。',
    skip: '跳转到正文', nav: ['功能', '安装', '更新日志', '订阅消息'],
    heroLabel: "", hero1: '一直', hero2: '和最喜欢的人在一起', hero3: '相伴左右。',
    heroBody: "按下键盘，宠物就会作出反应。你可以换上喜欢的图片，在它旁边显示待办列表和计时器。",
    githubDownload: '从 GitHub 下载', recommended: '推荐', directDownload: '从服务器直接下载',
    installBrew: '通过 Homebrew 安装', requirements: '支持 macOS 27 或更高版本', updatedToday: '今天更新', signed: '已通过 Apple 签名与公证',
    demoTitle: "按键反应预览", demoBubble: '试着按任意键！', demoTask: '一次专注一件事', demoHint: '点点这里，或在下方输入试试', demoPlaceholder: '你好，小伙伴！', demoLabel: '输入文字，体验宠物反应', demoCaption: '按键只用于触发宠物反应，不会保存或发送。', demoKey: '体验宠物反应',
    strip: ['自由自定义', '可爱的伙伴蹦蹦跳', '轻松下载图片包（计划中）'],
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
    focusLabel: "", focusTitle: "和最喜欢的人一起专注。", focusBody: "",
    screenshotAlt: 'Typing Pet 紧凑待办列表，显示两个示例任务和正在运行的专注计时器；截图为韩语', screenshotCaption: '应用实拍，显示韩语示例任务', focusTags: ['待办管理', '专注计时器', '番茄钟'],
    installLabel: "", installTitle: "安装 Typing Pet", installBody: "", zipTab: '下载 ZIP', brewTab: 'Homebrew',
    dmgDownload: '下载 DMG', dmgTab: '下载 DMG', dmgTitle: '通过 DMG 安装（推荐）', dmgSteps: ['下载 DMG，双击打开。', '将 TypingPet 拖到旁边的 Applications 文件夹。', '推出磁盘映像，然后从“应用程序”打开应用。'],
    zipTitle: "通过 ZIP 文件安装", zipSteps: ['下载 ZIP 并解压。', '将 TypingPet.app 移到“应用程序”文件夹。', '打开应用，按照输入监控指南完成设置。'],
    checksum: 'SHA-256', copyChecksum: '复制校验和', copyFailed: '复制失败', releasePage: '查看 GitHub 发行版', brewTitle: "使用 Homebrew 安装", brewBody: '在已安装 Homebrew 的 Mac 上运行以下命令。', brewAfter: '安装后，从“应用程序”打开 TypingPet。', brewUpdate: '使用 Homebrew 手动更新', copy: '复制命令', copied: '已复制！', copyError: '请选中命令并手动复制。',
    faqTitle: '你可能想了解这些。', faqs: [
      ['它会读取我输入的内容吗？', '不会读取或保存普通输入字符。它检测按键事件来作出反应。自定义按键反应仅在本机保存你主动注册的物理键码和修饰键组合。'],
      ['接下来会增加哪些功能？', '计划支持输入代码下载图片包，以及跨设备同步和备份设置。'],
      ['支持 Intel Mac 或 Windows 吗？', '此应用支持搭载 Apple Silicon、运行 macOS 27 或更高版本的 Mac。Windows 用户可以查看下方的 Typing Pet 项目。']
    ],
    faqWindowsLink: 'Windows 版 Typing Pet',
    notesLabel: "更新", notesTitle: "更新日志", notesBody: "正在琢磨细节……", allNotes: '查看全部更新日志', latest: '最新版本', prerelease: '预发布版', notesPageTitle: "更新日志", notesPageBody: "Typing Pet 各版本的改动记录。", back: '返回首页',
    creditLabel: "关于项目", creditTitle: "创作者", creditBody: '受 Windows 版 Typing Pet 启发，为 macOS 重新实现。\n\n这是我为了工作时使用而制作的。', inspiration: '启发本项目的原作', windowsVersion: '查看 Windows 版本', maker: '作者', makerDisplayName: '米埃尔', contact: '联系我们', source: '源代码', license: 'MIT 许可', footer: '一直与最喜欢的人相伴左右。',
    menuLabel: '主导航', languageLabel: '选择语言', installMethod: '安装方式', homeLabel: 'Typing Pet 首页', terminal: '终端',
  },
  'zh-Hant': {
    title: 'Typing Pet — 為每次敲鍵添點樂趣，為 Mac 添個小夥伴。',
    description: '一款會隨按鍵作出反應的 Mac 原生桌面寵物。你可以自訂圖片、管理待辦事項並使用專注計時器。支援 Apple Silicon Mac 和 macOS 27 或以上版本。',
    skip: '跳至主要內容', nav: ['功能', '安裝', '更新紀錄', '訂閱消息'],
    heroLabel: "", hero1: '一直', hero2: '和最喜歡的人在一起', hero3: '相伴左右。',
    heroBody: "按下鍵盤，寵物就會作出反應。你可以換上喜歡的圖片，在牠旁邊顯示待辦清單和計時器。",
    githubDownload: '從 GitHub 下載', recommended: '推薦', directDownload: '從伺服器直接下載',
    installBrew: '透過 Homebrew 安裝', requirements: '支援 macOS 27 或以上版本', updatedToday: '今天更新', signed: '已通過 Apple 簽署與公證',
    demoTitle: "按鍵反應預覽", demoBubble: '試著按任意鍵！', demoTask: '一次專注一件事', demoHint: '點點這裡，或在下方輸入試試', demoPlaceholder: '你好，小夥伴！', demoLabel: '輸入文字，體驗寵物反應', demoCaption: '按鍵只用來觸發寵物反應，不會儲存或傳送。', demoKey: '體驗寵物反應',
    strip: ['自由自訂', '可愛的夥伴蹦蹦跳', '輕鬆下載圖片包（規劃中）'],
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
    focusLabel: "", focusTitle: "和最喜歡的人一起專注。", focusBody: "",
    screenshotAlt: 'Typing Pet 精簡待辦列表，顯示兩個範例任務和正在執行的專注計時器；截圖為韓文', screenshotCaption: 'App 實拍，顯示韓文範例任務', focusTags: ['待辦管理', '專注計時器', '番茄鐘'],
    installLabel: "", installTitle: "安裝 Typing Pet", installBody: "", zipTab: '下載 ZIP', brewTab: 'Homebrew',
    dmgDownload: '下載 DMG', dmgTab: '下載 DMG', dmgTitle: '透過 DMG 安裝（建議）', dmgSteps: ['下載 DMG，按兩下開啟。', '將 TypingPet 拖到旁邊的 Applications 檔案夾。', '退出磁碟映像檔，然後從「應用程式」開啟 App。'],
    zipTitle: "透過 ZIP 檔案安裝", zipSteps: ['下載 ZIP 並解壓縮。', '將 TypingPet.app 移到「應用程式」檔案夾。', '開啟 App，按照輸入監控指南完成設定。'],
    checksum: 'SHA-256', copyChecksum: '複製校驗碼', copyFailed: '複製失敗', releasePage: '查看 GitHub 發行版本', brewTitle: "使用 Homebrew 安裝", brewBody: '在已安裝 Homebrew 的 Mac 上執行以下指令。', brewAfter: '安裝後，從「應用程式」開啟 TypingPet。', brewUpdate: '使用 Homebrew 手動更新', copy: '拷貝指令', copied: '已拷貝！', copyError: '請選取指令並手動拷貝。',
    faqTitle: '你可能想了解這些。', faqs: [
      ['牠會讀取我輸入的內容嗎？', '不會讀取或儲存一般輸入字元。它偵測按鍵事件來作出反應。自訂按鍵反應僅在本機儲存你主動登錄的實體鍵碼和修飾鍵組合。'],
      ['接下來會增加哪些功能？', '計畫支援輸入代碼下載圖片包，以及跨裝置同步和備份設定。'],
      ['支援 Intel Mac 或 Windows 嗎？', '此 App 支援搭載 Apple Silicon、執行 macOS 27 或以上版本的 Mac。Windows 使用者可以查看下方的 Typing Pet 專案。']
    ],
    faqWindowsLink: 'Windows 版 Typing Pet',
    notesLabel: "更新", notesTitle: "更新紀錄", notesBody: "正在琢磨細節……", allNotes: '查看全部更新紀錄', latest: '最新版本', prerelease: '預先發行版', notesPageTitle: "更新紀錄", notesPageBody: "Typing Pet 各版本的變更紀錄。", back: '返回首頁',
    creditLabel: "關於專案", creditTitle: "創作者", creditBody: '受 Windows 版 Typing Pet 啟發，為 macOS 重新實作。\n\n這是我為了工作時使用而製作的。', inspiration: '啟發本專案的原作', windowsVersion: '查看 Windows 版本', maker: '作者', makerDisplayName: '米埃爾', contact: '聯絡我們', source: '原始碼', license: 'MIT 授權', footer: '一直與最喜歡的人相伴左右。',
    menuLabel: '主要導覽', languageLabel: '選擇語言', installMethod: '安裝方式', homeLabel: 'Typing Pet 首頁', terminal: '終端機',
  },
};
