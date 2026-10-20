#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
check_dir="${TODO_CHECK_BUILD_DIR:-$PWD/.build/todo-checks}"
mkdir -p "$check_dir/module-cache"
swiftc -parse-as-library -swift-version 5 -module-cache-path "$check_dir/module-cache" \
    Sources/TypingPet/AppEnvironment.swift Sources/TypingPet/TodoState.swift Sources/TypingPet/FocusTimerEngine.swift \
    Sources/TypingPet/TodoStore.swift Sources/TypingPet/PetWindowGeometry.swift \
    Sources/TypingPet/TodoBubbleGeometry.swift Sources/TypingPet/TextEditingShortcuts.swift scripts/check_todo.swift \
    -o "$check_dir/check-todo"
"$check_dir/check-todo"
