# Todo and focus timer

The Todo feature is optional. The first launch shows the pet. Move the pointer near the pet and select `할 일`.
The menu bar also has `할 일 표시`.

## Add and manage Todos

1. Enter a title in `할 일 추가…`.
2. Press Enter.
3. Select the circle to complete the Todo.

The list keeps open Todos across dates. `오늘 완료` shows only Todos completed on the current local date.
Open that section to undo completion. Use the row menu to delete a Todo. Deletion hides the Todo and keeps its sessions.
The title tooltip shows the full title.

## Use a timer

Each Todo starts with a 20-minute setting. The main button starts the selected setting.
The arrow opens a popover. Select 10, 20, or 30 minutes, a custom duration, or count-up.
Custom durations use whole minutes from 1 through 999. Selecting a setting does not start a timer.
Each Todo keeps its own setting.

Starting a timer opens the compact focus view. It shows the title, a tomato, and the timer.
Move the pointer over the view to show pause, resume, and stop controls.
Select the title or time to open the list. The timer continues while you use the list.
The header button returns to the compact view.

A countdown stops at zero. The compact expiry view offers extension and finish.
The extension arrow changes the duration. The main extension button starts that duration in the same session.
Time spent at zero does not count. Finishing a timer leaves its Todo open.
Completing the active Todo finishes its timer first.

Starting another Todo asks for confirmation. The old timer keeps its current state until you select `전환`.
Cancel keeps the old session. Confirmation finishes it and starts one new session.

## Show, hide, and move

The pet and Todo UI use separate panels. Position lock keeps mouse clicks passing through the pet.
The Todo panel and entry button continue to receive clicks. The Todo panel can receive keyboard focus.
The Todo panel follows pet movement and size changes. It uses the pet display's visible frame.
It first tries the space above the pet, then the sides and the space below.
The Todo panel uses the same window level and Space policy as the pet.
Pointer avoidance stops while you operate the Todo panel or entry button.

`할 일 숨기기` hides the Todo UI and keeps the timer running. Hiding the pet hides both panels.
Use `할 일 표시` in the menu bar to restore the pet and list.
Settings has a `할 일` tab with feature and visibility controls.

## Time and local storage

The record file is:

```text
~/Library/Application Support/TypingPet/todo-state.json
```

Settings > `할 일` > `기록 데이터 열기` reveals this file in Finder.
The file holds schema version 1, feature preferences, Todos, sessions, and extension segments.
Dates use UTC ISO 8601. The completed list uses the current local calendar.
Actual seconds keep fractions. Each session total equals the sum of its segments.

The engine measures monotonic elapsed time. It does not count timer callbacks.
Countdown segments clamp at their configured duration. Paused time and expired waiting time do not count.
The app saves each state change and checkpoints running time about every five seconds.
Writes use atomic replacement. A damaged or unsupported file blocks changes and remains unchanged.
Save errors appear in the panel. A failed save during normal quit offers retry, cancel, or quit without saving.

Sleep pauses and saves the active timer. Wake does not resume it.
Normal quit saves a paused session. A restart restores a running checkpoint as paused.
The app does not add offline time. A crash can lose the time since the last successful checkpoint.
Copy the JSON file to make a backup. Quit the app before you restore or edit it.
The app has no account, server, sync, notifications, or statistics screen.

## Tests

With full Xcode selected:

```sh
swift test
swift build -c release
```

The tests cover accumulation, extension, pause, switching, local midnight, JSON storage, and recovery.
The existing pet tests remain in the test target.
CI runs tests and a release build on macOS for `main`, `feat/**`, and pull requests.

Command Line Tools can lack XCTest. Run the separate executable checks in that environment:

```sh
./scripts/check_todo.sh
```

These checks use temporary files and injected clocks. They do not use your Todo record.
They supplement the XCTest suite. They do not replace it.

For an isolated debug UI test, set `TYPINGPET_TODO_TEST_PATH` to a temporary JSON path.
Run a debug build with `--todo-preview --show-todos` to skip input permission prompts and open the list.
Use a separate bundle identifier to keep pet preferences separate.
Release builds ignore these test options and always use the normal record path.

Manual checks still require real displays, Space changes, sleep/wake, and input permission changes.
A successful compile does not prove those checks.
