# Codex Chat Log Browser (Flutter)

Desktop Flutter UI for browsing `.codex` chat log JSONL files.

## What it does

- Loads all `.jsonl` files under a sessions directory (defaults to `$HOME/.codex/sessions`).
- Shows chats (sessions) in a selectable list.
- Normalizes multiple log schemas found in sample files.
- Filters records by category:
  - Prompt
  - Assistant Response
  - Assistant Commentary
  - Assistant Final
  - Instruction
  - Tool Call / Tool Output
  - Reasoning
  - Event / Meta / State
- Searches within the selected chat.
- Auto-expand/collapse by message type.
- Visualizes full raw JSON for every record.

## Run

1. Install Flutter SDK.
2. From this repository root:
   - `flutter pub get`
   - `flutter run -d macos` (or your platform)

By default, the app starts with `$HOME/.codex/sessions` and falls back to `<cwd>/sessions` if `HOME` is unavailable.

Note: To actually make the app work on macOS, you need to open the folder selection dialog and select a folder to give the app permissions to read it.