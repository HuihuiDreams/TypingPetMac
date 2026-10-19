import AppKit
import SwiftUI

private enum TodoTimeText {
    static func clock(_ seconds: Double, countdown: Bool) -> String {
        let value = Int(countdown ? ceil(max(0, seconds)) : floor(max(0, seconds)))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    static func total(_ seconds: Double) -> String {
        let value = Int(seconds)
        if value < 60 { return "누적 \(value)초" }
        if value < 3600 { return "누적 \(value / 60)분" }
        return "누적 \(value / 3600)시간 \(value / 60 % 60)분"
    }
}

struct TodoBubbleView: View {
    @ObservedObject var store: TodoStore
    @State private var title = ""
    @State private var hovering = false
    @State private var completedExpanded = false
    @State private var pendingStart: UUID?
    @State private var pendingDelete: UUID?
    @State private var extensionPreference = TimerPreference()
    @FocusState private var inputFocused: Bool

    private var session: FocusSession? { store.engine.activeSession }
    private var activeTitle: String {
        store.engine.state.todos.first { $0.id == session?.todoId }?.title ?? ""
    }
    private var clockText: String {
        TodoTimeText.clock(store.engine.displaySeconds, countdown: session?.modeAtStart == .countdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = store.errorMessage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(store.loadBlocked ? "Cannot read Todo data" : "Cannot save Todo data", systemImage: "exclamationmark.triangle.fill").font(.headline)
                        Text(error).font(.caption).textSelection(.enabled)
                        HStack {
                            Button("기록 데이터 열기") { revealData() }
                            if !store.loadBlocked { Button("Retry save") { store.persist() } }
                        }
                    }
                }.frame(maxHeight: store.loadBlocked ? .infinity : 110)
            }
            if !store.loadBlocked {
                if store.expanded || session == nil { expandedList }
                else if session?.status == .expired { expiredPrompt }
                else { compactFocus }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.2)))
        .onHover { hovering = $0 }
        .onChange(of: session?.status) { status in
            if status == .expired { resetExtension() }
        }
        .onAppear { if session?.status == .expired { resetExtension() } }
        .alert("타이머 전환", isPresented: Binding(get: { pendingStart != nil }, set: { if !$0 { pendingStart = nil } })) {
            Button("취소", role: .cancel) { pendingStart = nil }
            Button("전환") {
                if let id = pendingStart { start(id, confirmed: true) }
                pendingStart = nil
            }
        } message: {
            let nextTitle = store.engine.state.todos.first { $0.id == pendingStart }?.title ?? ""
            Text("‘\(activeTitle)’의 타이머를 종료하고 ‘\(nextTitle)’를 시작할까요?")
        }
        .alert("할 일을 삭제할까요?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("취소", role: .cancel) { pendingDelete = nil }
            Button("삭제", role: .destructive) {
                if let id = pendingDelete { store.change { $0.delete(id) } }
                pendingDelete = nil
            }
        } message: { Text("시간 기록은 유지합니다.") }
    }

    private var expandedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppEnvironment.isDevelopment ? "오늘 할 일 · DEV" : "오늘 할 일").font(.headline)
                Spacer()
                if session != nil {
                    Button { store.expanded = false } label: { Image(systemName: "chevron.down") }
                        .help("집중 말풍선으로 접기").accessibilityLabel("집중 말풍선으로 접기")
                }
                Button { store.hide() } label: { Image(systemName: "minus") }
                    .help("할 일 숨기기").accessibilityLabel("할 일 숨기기")
            }.buttonStyle(.borderless)
            if session != nil {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🍅 \(activeTitle)").lineLimit(2).help(activeTitle)
                        Text("\(clockText)\(session?.status == .paused ? " · 일시정지" : "")")
                            .monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    if session?.status == .expired {
                        Button("연장 / 끝내기") { store.expanded = false }
                    } else { timerControls }
                }
                .font(.caption)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.engine.openTodos.isEmpty {
                        Text("할 일을 추가하세요.").foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    ForEach(store.engine.openTodos) { todo in todoRow(todo, completed: false) }
                    Divider()
                    let completed = store.engine.completedToday()
                    DisclosureGroup("오늘 완료 \(completed.count)개", isExpanded: $completedExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(completed) { todo in todoRow(todo, completed: true) }
                        }.padding(.top, 8)
                    }
                }.padding(.trailing, 4)
            }
            HStack(spacing: 8) {
                TextField("할 일 추가…", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit { addTodo() }
                    .accessibilityLabel("할 일 추가")
                Button { addTodo() } label: { Image(systemName: "plus") }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("할 일 추가")
            }
            .onAppear { DispatchQueue.main.async { inputFocused = true } }
        }
    }

    private func todoRow(_ todo: TodoItem, completed: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { store.change { $0.setCompleted(todo.id, completed: !completed) } } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle").font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(todo.title) \(completed ? "완료 취소" : "완료")")
            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title).strikethrough(completed).lineLimit(2).help(todo.title)
                    .textSelection(.enabled)
                HStack(alignment: .center, spacing: 4) {
                    Text(TodoTimeText.total(store.engine.totalSeconds(for: todo.id)))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    if !completed && session?.todoId != todo.id {
                        TimerSplitButton(preference: todo.timerPreference, suffix: "시작", allowsCountup: true, onSelect: { preference in
                            store.change { $0.setPreference(preference, for: todo.id) }
                        }, onStart: { requestStart(todo.id) })
                    } else if session?.todoId == todo.id {
                        Text("현재 타이머").font(.caption).foregroundStyle(.tint)
                    }
                }
            }
            Menu {
                Button("삭제…", role: .destructive) { pendingDelete = todo.id }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 18)
                .accessibilityLabel("\(todo.title) 메뉴")
        }
    }

    private var compactFocus: some View {
        VStack(spacing: 8) {
            Button { store.expanded = true } label: {
                VStack(spacing: 6) {
                    Text("🍅 \(activeTitle)").font(.headline).lineLimit(2).help(activeTitle)
                    Text(clockText).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                }.frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("\(activeTitle), 목록 펼치기").accessibilityValue(clockText)
            if session?.status == .paused { Text("일시정지").font(.caption).foregroundStyle(.secondary) }
            HStack { timerControls; Button("숨기기") { store.hide() } }
                .font(.caption)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .accessibilityHidden(!hovering)
        }.frame(maxWidth: .infinity)
    }

    private var timerControls: some View {
        HStack(spacing: 6) {
            Button(session?.status == .paused ? "재개" : "일시정지") {
                store.change { engine in
                    if engine.activeSession?.status == .paused { engine.resume() } else { engine.pause() }
                }
            }
            Button("종료") { finish() }
        }
    }

    private var expiredPrompt: some View {
        VStack(spacing: 10) {
            Text("🍅 \(activeTitle)").font(.headline).lineLimit(2).help(activeTitle)
            Text("00:00").font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
            Text("집중 시간이 끝났어요").font(.caption).foregroundStyle(.secondary)
            HStack {
                TimerSplitButton(preference: extensionPreference, suffix: "연장", allowsCountup: false,
                    onSelect: { extensionPreference = $0 }, onStart: {
                        store.change { $0.extend(minutes: Int((extensionPreference.seconds ?? 1200) / 60)) }
                    })
                Button("끝내기") { finish() }
            }
        }.frame(maxWidth: .infinity)
    }

    private func resetExtension() {
        extensionPreference = TimerPreference(seconds: session?.activeSegments.last?.configuredSeconds ?? 1200)
    }
    private func addTodo() {
        let value = title
        store.change { _ = $0.addTodo(value) }
        title = ""
        inputFocused = true
    }
    private func requestStart(_ id: UUID) {
        if let current = session, current.todoId != id { pendingStart = id }
        else { start(id, confirmed: false) }
    }
    private func start(_ id: UUID, confirmed: Bool) {
        var started = false
        store.change { started = $0.start(id, replaceActive: confirmed) }
        if started { store.expanded = false; inputFocused = false }
    }
    private func finish() { store.change { $0.finish() }; store.expanded = true }
    private func revealData() { NSWorkspace.shared.activateFileViewerSelecting([store.storage.url]) }
}

private struct TimerSplitButton: View {
    let preference: TimerPreference
    let suffix: String
    let allowsCountup: Bool
    let onSelect: (TimerPreference) -> Void
    let onStart: () -> Void
    @State private var showingOptions = false
    @State private var custom = false
    @State private var minutes = "20"

    private var buttonTitle: String {
        preference.mode == .countup ? "카운트업 \(suffix)" : "\(Int((preference.seconds ?? 1200) / 60))분 \(suffix)"
    }
    private var customValue: TimerPreference? {
        guard let number = Int(minutes) else { return nil }
        return TimerPreference.countdown(minutes: number)
    }
    var body: some View {
        HStack(spacing: 0) {
            Button(buttonTitle, action: onStart)
                .padding(.horizontal, 8).padding(.vertical, 5)
            Divider().frame(height: 18)
            Button {
                custom = false
                minutes = String(Int((preference.seconds ?? 1200) / 60))
                showingOptions.toggle()
            } label: {
                Image(systemName: "chevron.right").padding(.horizontal, 8).padding(.vertical, 5)
            }
            .accessibilityLabel("\(suffix) 타이머 설정")
            .help("타이머 설정")
            .popover(isPresented: $showingOptions, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 8) {
                    if custom {
                        Text("직접 설정 (1~999분)").font(.headline)
                        TextField("분", text: $minutes).textFieldStyle(.roundedBorder)
                            .onSubmit { applyCustom() }
                        if customValue == nil { Text("1~999 사이의 정수를 입력하세요.").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            Button("취소") { showingOptions = false }
                            Spacer()
                            Button("적용") { applyCustom() }.disabled(customValue == nil)
                        }
                    } else {
                        ForEach([10, 20, 30], id: \.self) { value in
                            Button {
                                onSelect(.countdown(minutes: value)!); showingOptions = false
                            } label: {
                                HStack {
                                    Text("\(value)분")
                                    Spacer()
                                    if preference == .countdown(minutes: value) { Image(systemName: "checkmark") }
                                }.contentShape(Rectangle())
                            }
                        }
                        Button("직접 설정…") { custom = true }
                        if allowsCountup {
                            Divider()
                            Button {
                                onSelect(.countup); showingOptions = false
                            } label: {
                                HStack { Text("카운트업"); Spacer(); if preference.mode == .countup { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                }.buttonStyle(.plain).padding(14).frame(width: 210)
            }
        }
        .font(.caption)
        .buttonStyle(.plain)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
        .fixedSize()
    }
    private func applyCustom() {
        guard let value = customValue else { return }
        onSelect(value); showingOptions = false
    }
}

struct TodoSettingsView: View {
    @ObservedObject var store: TodoStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("할 일과 집중 타이머").font(.title2).bold()
            Toggle("할 일 기능 사용", isOn: Binding(
                get: { store.engine.state.featurePreferences.enabled },
                set: { value in
                    store.expanded = true
                    store.change { $0.setFeature(enabled: value, hidden: false) }
                }))
                .disabled(store.loadBlocked)
            Toggle("말풍선 표시", isOn: Binding(
                get: { !store.engine.state.featurePreferences.bubbleHidden },
                set: { value in if value { store.show() } else { store.hide() } }))
                .disabled(!store.engine.state.featurePreferences.enabled || store.loadBlocked)
            Text("말풍선을 숨겨도 실행 중인 타이머는 유지합니다. 잠자기와 앱 종료 시에는 일시정지합니다.")
                .foregroundStyle(.secondary)
            Divider()
            Button("기록 데이터 열기") { NSWorkspace.shared.activateFileViewerSelecting([store.storage.url]) }
            Text(store.storage.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("할 일 제목, 완료 날짜, 타이머 설정과 실제 집중 시간을 이 Mac의 JSON 파일에 저장합니다.")
                .foregroundStyle(.secondary)
            if let error = store.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Spacer()
        }.padding(24)
    }
}
