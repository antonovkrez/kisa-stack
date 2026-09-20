# Каркас личного харнеса — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Одна команда `overlay/harness.sh apply` разворачивает скиллы, правила, хуки и подключение MCP deploychan из форка `kisa-stack` в Claude Code, Codex и Hermes на Windows и Linux, не ломая существующие настройки.

**Architecture:** Слой `overlay/` поверх нетронутого апстрима. `harness.sh` (bash) готовит желаемое содержимое каждого целевого файла в `.build/render/`, показывает `diff -u` и только в режиме `apply` делает бэкап и пишет. Скиллы ставит `install.sh` апстрима без единой правки — через стейджинг-каталог. Правила вставляются управляемым блоком между маркерами, `settings.json` сливается через `jq`.

**Tech Stack:** bash >= 4.4, awk, sed, diff, cmp, find, jq. Тесты — чистый bash без фреймворка. Лаунчер для Windows — PowerShell 5.1.

Спек: `overlay/docs/specs/2026-09-20-harness-skeleton-design.md`.

## Global Constraints

- Все новые файлы — только внутри `overlay/`. Ни один файл апстрима не меняется, включая корневые `.gitignore` и `README.md`.
- `install.sh` апстрима используется буквально: копируется в стейджинг (с удалением `\r`) и запускается оттуда. Его логика не дублируется.
- В чужих файлах харнес владеет только своим блоком между маркерами или своими ключами. Остальное сохраняется байт-в-байт.
- Повторный `apply` без изменений во входных данных не меняет ни одного файла и не создает бэкапов.
- `plan` не пишет ничего вне каталога сборки (`overlay/.build/`, в тестах — `HARNESS_BUILD_DIR`).
- Зависимости: только bash >= 4.4, coreutils, `diff`, `sed`, `awk`, `find`, `cmp`, `jq`. Python и Node не используются.
- Каждое сообщение об ошибке начинается с ASCII-кода: `E_PREREQ`, `E_PROFILE`, `E_WIKI_DIR`, `E_ANCHOR`, `E_PLACEHOLDER`, `E_MARKER`, `E_JSON`. Строки статуса начинаются с ASCII-токена (`NEW`, `SAME`, `CHANGED`, `WROTE`, `BACKUP`, `SKILL`, `SWEPT`, `KEPT`, `MCP`, `RUNTIME`, `SKIP`). Тесты опираются на эти токены; русский текст ищут только через `grep -F` (побайтное сравнение, от локали не зависит).
- Наличие `\r` в файле нельзя проверять через `grep $'\r'`: в Git Bash такой шаблон совпадает с каждой строкой (проверено на этой машине). В тестах — только помощник `has_cr` из `tests/run.sh`. Удаление `\r` через `sed 's/\r$//'` и `awk sub(/\r$/, "")` работает корректно.
- Конвенция репозитория: в коммитимых файлах нет буквы U+0451 и U+0401 (см. коммит `b68483e`). Пишите через «е».
- Все текстовые файлы — с окончаниями LF.
- Сообщения коммитов — на русском, в стиле апстрима («Добавлен ...», «Исправлена ...»), с трейлером `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Нативный `jq.exe` на Windows отдает CRLF и портит аргументы, похожие на пути. Поэтому `jq` вызывается только через обертку `jqx` (Task 1), а пути к файлам передаются через `native_path`.
- В конвейерах под `set -o pipefail` нельзя писать `producer | grep -q`: `grep -q` выходит раньше, продюсер получает SIGPIPE, конвейер считается упавшим. Сначала сохранить вывод в переменную, потом `grep -q ... <<< "$var"`.
- Запуск тестов: `bash overlay/tests/run.sh` из корня репо (на Windows — в Git Bash). Если `jq` не виден в сессии после установки — перезапустить приложение. Временный обход: `export PATH="$PATH:$LOCALAPPDATA/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe"`.

## Карта файлов

| Файл | Ответственность | Задача |
|---|---|---|
| `overlay/harness.sh` | точка входа, порядок шагов | 1, 4, 5, 6, 7 |
| `overlay/lib/common.sh` | вывод, ошибки, заметки, `jqx`, `native_path`, `copy_lf`, `runtime_home` | 1 |
| `overlay/lib/detect.sh` | пререквизиты, профиль, обнаружение рантаймов | 1 |
| `overlay/lib/block.sh` | управляемый блок между маркерами | 2 |
| `overlay/lib/render.sh` | рендеринг правил из шаблона апстрима | 3 |
| `overlay/lib/pending.sh` | реестр предложенных записей, показ диффов, запись | 4 |
| `overlay/lib/backup.sh` | бэкапы файлов, перенос backup-папок скиллов | 4, 5 |
| `overlay/lib/rules.sh` | связка: рендер + блок + реестр для CLAUDE.md и AGENTS.md | 4 |
| `overlay/lib/stage.sh` | стейджинг скиллов и вызов `install.sh` | 5 |
| `overlay/lib/settings.sh`, `overlay/lib/settings.jq` | хуки и слияние `settings.json` | 6 |
| `overlay/lib/mcp.sh` | подключение deploychan | 7 |
| `overlay/harness.ps1` | лаунчер для Windows | 8 |
| `overlay/tests/run.sh` | раннер и помощники тестов | 1 |
| `overlay/tests/cases/*.sh` | тесты по областям | 1–8 |
| `overlay/profile.example.env`, `overlay/.gitignore`, `overlay/.gitattributes`, `overlay/skills/.gitkeep`, `overlay/rules/*.md` | конфигурация слоя | 1 |
| `overlay/README.md` | документация слоя | 8 |

Переменные окружения для тестов (все необязательны): `HARNESS_PROFILE`, `HARNESS_BUILD_DIR`, `HARNESS_UPSTREAM_DIR`, `HARNESS_OVERLAY_SKILLS`, `HARNESS_OVERLAY_RULES`, `HARNESS_CLAUDE_BIN`, `HARNESS_TS`.

---

### Task 1: Скелет слоя, раннер тестов, окружение

**Files:**
- Create: `overlay/.gitignore`, `overlay/.gitattributes`, `overlay/profile.example.env`, `overlay/skills/.gitkeep`, `overlay/rules/claude.md`, `overlay/rules/agents.md`
- Create: `overlay/lib/common.sh`, `overlay/lib/detect.sh`, `overlay/harness.sh`
- Test: `overlay/tests/run.sh`, `overlay/tests/cases/env.sh`

**Interfaces:**
- Consumes: ничего.
- Produces:
  - `common.sh`: `info <msg>`, `warn <msg>`, `die <msg>` (exit 1), `note <msg>`, `print_notes`, `copy_lf <src> <dst>`, `native_path <path>` (stdout), `jqx <jq-args...>`, `runtime_home <claude|codex|hermes>` (stdout).
  - `detect.sh`: `check_prereqs`, `load_profile`, `validate_profile`, `detect_runtimes` (заполняет массив `ACTIVE_RUNTIMES`), `has_runtime <rt>`.
  - Глобальные переменные профиля: `RUNTIMES`, `WIKI_ENABLED`, `WIKI_DIR`, `AUTO_MEMORY_OFF`, `MCP_OBSIDIAN`, `DATAWEAVE_ENABLED`, `DATAWEAVE_REPO`, `RTK_ENABLED`, `HOOK_COMMAND_STYLE` (`direct`|`explicit`), `HOOK_BASH`.
  - Глобальные переменные `harness.sh`: `OVERLAY_DIR`, `REPO_DIR`, `UPSTREAM_DIR`, `OVERLAY_SKILLS_DIR`, `OVERLAY_RULES_DIR`, `BUILD_DIR`, `RENDER_DIR`.
  - `tests/run.sh`: `new_sandbox`, `write_profile [строки...]`, `run_ok <args>`, `run_fail <code> <args>`, `load_libs`, `fail`, `assert_file`, `assert_no_path`, `assert_contains <file> <str>`, `assert_not_contains <file> <str>`, `assert_eq <got> <want>`, `tree_hash <dir>`, `jqt <jq-args>`, `has_cr <file>`; переменные `SB`, `HARNESS`, `OVERLAY_DIR`, `REPO_DIR`.

- [ ] **Step 1: Создать файлы конфигурации слоя**

`overlay/.gitignore`:

```gitignore
profile.env
.build/
```

`overlay/.gitattributes`:

```gitattributes
* text eol=lf
```

`overlay/skills/.gitkeep`, `overlay/rules/claude.md`, `overlay/rules/agents.md` — пустые файлы (0 байт). Непустой `rules/*.md` дописывается в конец правил, поэтому комментариев внутри быть не должно.

```bash
mkdir -p overlay/skills overlay/rules overlay/lib overlay/tests/cases
: > overlay/skills/.gitkeep
: > overlay/rules/claude.md
: > overlay/rules/agents.md
```

`overlay/profile.example.env`:

```bash
# Профиль харнеса. Скопируйте в overlay/profile.env и заполните.
# Пути пишите с прямыми слэшами: C:/Users/me/wiki

# Куда ставить. Рантайм без домашнего каталога будет пропущен.
RUNTIMES="claude codex hermes"

# Вики-секция в правилах и хуки-якоря. При 1 папка WIKI_DIR должна существовать.
WIKI_ENABLED=1
WIKI_DIR=""

# 1 - записать autoMemoryEnabled:false и оставить в правилах подсекцию "Память".
# Держите 0, пока не появится пайплайн записи в вики.
AUTO_MEMORY_OFF=0

# 1 - оставить в правилах абзац про MCP-сервер mcp-obsidian.
MCP_OBSIDIAN=0

# 1 - оставить упоминания ObsidianDataWeave; тогда нужен путь к клону.
DATAWEAVE_ENABLED=0
DATAWEAVE_REPO=""

# 1 - оставить в AGENTS.md пункт про rtk wrappers.
RTK_ENABLED=0

# Форма команды хука в settings.json:
#   direct   - как у апстрима: $HOME/.claude/hooks/wiki-anchor.sh
#   explicit - "<HOOK_BASH>" "<абсолютный путь к хуку>"
HOOK_COMMAND_STYLE=direct
HOOK_BASH=""
```

- [ ] **Step 2: Написать раннер тестов**

`overlay/tests/run.sh`:

```bash
#!/usr/bin/env bash
# Тесты харнеса. Запуск: bash overlay/tests/run.sh [часть-имени-теста]
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$(dirname "$TESTS_DIR")"
REPO_DIR="$(dirname "$OVERLAY_DIR")"
HARNESS="$OVERLAY_DIR/harness.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file()         { [ -f "$1" ] || fail "нет файла: $1"; }
assert_no_path()      { [ ! -e "$1" ] || fail "путь не должен существовать: $1"; }
assert_contains()     { grep -qF -- "$2" "$1" || fail "в $1 нет строки: $2"; }
assert_not_contains() { ! grep -qF -- "$2" "$1" || fail "в $1 есть лишняя строка: $2"; }
assert_eq()           { [ "$1" = "$2" ] || fail "ожидалось '$2', получено '$1'"; }

tree_hash() {
  ( cd "$1" && { find . | sort; find . -type f -exec cksum {} + | sort; } | cksum )
}

jqt() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@" | tr -d '\r'; }

# Есть ли в файле \r. Сравнение по числу байт: grep $'\r' в Git Bash ненадежен.
has_cr() {
  [ "$(tr -d '\r' < "$1" | wc -c | tr -d ' ')" != "$(wc -c < "$1" | tr -d ' ')" ]
}

write_profile() {
  {
    printf 'WIKI_DIR="%s"\n' "$SB/wiki"
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$HARNESS_PROFILE"
}

new_sandbox() {
  SB="$(mktemp -d)"
  trap 'rm -rf "$SB"' EXIT
  export HOME="$SB/home"
  export CODEX_HOME="$HOME/.codex"
  export HERMES_HOME="$HOME/.hermes"
  export HARNESS_PROFILE="$SB/profile.env"
  export HARNESS_BUILD_DIR="$SB/build"
  export HARNESS_CLAUDE_BIN="$SB/no-such-claude"
  export HARNESS_OVERLAY_SKILLS="$SB/overlay-skills"
  export HARNESS_OVERLAY_RULES="$SB/overlay-rules"
  export HARNESS_TS="20260101-000000"
  mkdir -p "$HOME/.claude" "$CODEX_HOME" "$HERMES_HOME" "$SB/wiki" \
           "$HARNESS_OVERLAY_SKILLS" "$HARNESS_OVERLAY_RULES"
  write_profile
}

run_harness() { bash "$HARNESS" "$@" > "$SB/out.log" 2>&1; }
run_ok() { run_harness "$@" || fail "harness $* упал:"$'\n'"$(cat "$SB/out.log")"; }
run_fail() {
  local code="$1"; shift
  if run_harness "$@"; then fail "harness $* должен был упасть с $code"; fi
  grep -qF -- "$code" "$SB/out.log" || fail "в выводе нет $code:"$'\n'"$(cat "$SB/out.log")"
}

load_libs() {
  local lib
  for lib in "$OVERLAY_DIR"/lib/*.sh; do
    # shellcheck disable=SC1090
    source "$lib"
  done
}

for case_file in "$TESTS_DIR"/cases/*.sh; do
  # shellcheck disable=SC1090
  source "$case_file"
done

pattern="${1:-}"
passed=0
failed=()
for t in $(declare -F | awk '{ print $3 }' | grep '^test_' | sort); do
  if [ -n "$pattern" ] && [[ "$t" != *"$pattern"* ]]; then continue; fi
  printf '%s ... ' "$t"
  out="$( ( new_sandbox; "$t" ) 2>&1 )"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    passed=$((passed + 1)); echo ok
  else
    failed+=("$t"); echo FAIL
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
done

printf '\npassed: %d, failed: %d\n' "$passed" "${#failed[@]}"
[ "${#failed[@]}" -eq 0 ]
```

Примечание для исполнителя: тест — это функция `test_*`, которая выполняется в подоболочке со свежей песочницей. Проверки завершают подоболочку через `fail` (явный `exit 1`), поэтому `set -e` в тестах не нужен и не используется.

- [ ] **Step 3: Написать падающие тесты окружения**

`overlay/tests/cases/env.sh`:

```bash
test_env_plan_ok_on_clean_sandbox() {
  run_ok plan
  assert_contains "$SB/out.log" 'RUNTIME claude'
  assert_contains "$SB/out.log" 'RUNTIME codex'
  assert_contains "$SB/out.log" 'RUNTIME hermes'
}

test_env_profile_missing() {
  rm -f "$HARNESS_PROFILE"
  run_fail E_PROFILE plan
}

test_env_bad_flag() {
  write_profile 'WIKI_ENABLED=yes'
  run_fail E_PROFILE plan
}

test_env_backslash_path() {
  write_profile "WIKI_DIR='C:\\Users\\me\\wiki'"
  run_fail E_PROFILE plan
}

test_env_wiki_dir_missing() {
  rm -rf "$SB/wiki"
  run_fail E_WIKI_DIR plan
}

test_env_wiki_off_needs_no_dir() {
  rm -rf "$SB/wiki"
  write_profile 'WIKI_ENABLED=0'
  run_ok plan
}

test_env_explicit_style_needs_bash() {
  write_profile 'HOOK_COMMAND_STYLE=explicit'
  run_fail E_PROFILE plan
}

test_env_runtime_skipped() {
  rm -rf "$HERMES_HOME"
  run_ok plan
  assert_contains "$SB/out.log" 'SKIP    runtime hermes'
}

test_env_no_runtimes() {
  rm -rf "$HOME/.claude" "$CODEX_HOME" "$HERMES_HOME"
  run_fail E_PREREQ plan
}

test_env_unknown_mode() {
  if run_harness frobnicate; then fail "неизвестный режим должен падать"; fi
}

test_env_jq_missing() {
  (
    load_libs
    command() { if [ "${2:-}" = jq ]; then return 1; fi; builtin command "$@"; }
    check_prereqs
  ) > "$SB/out.log" 2>&1 && fail "без jq проверка должна падать"
  assert_contains "$SB/out.log" E_PREREQ
}
```

- [ ] **Step 4: Запустить тесты и убедиться, что они падают**

Run: `bash overlay/tests/run.sh env`
Expected: все `test_env_*` — FAIL (нет `overlay/harness.sh`), итог `failed: 11`, код возврата 1.

- [ ] **Step 5: Написать `common.sh`**

`overlay/lib/common.sh`:

```bash
# Общие функции: вывод, ошибки, заметки для человека, обертки для Windows.
# Сообщение об ошибке всегда начинается с ASCII-кода E_* - на него опираются тесты.

info() { printf '[harness] %s\n' "$*"; }
warn() { printf '[harness] WARN    %s\n' "$*" >&2; }
die()  { printf '[harness] %s\n' "$*" >&2; exit 1; }

NOTES=()
note() { NOTES+=("$*"); }
print_notes() {
  [ "${#NOTES[@]}" -gt 0 ] || return 0
  printf '\n[harness] Сделать вручную:\n'
  local n
  for n in "${NOTES[@]}"; do printf '  - %s\n' "$n"; done
}

# Копия файла без \r в концах строк (core.autocrlf на Windows).
copy_lf() {
  mkdir -p "$(dirname "$2")"
  sed 's/\r$//' "$1" > "$2"
}

# Путь в форме, понятной нативным Windows-бинарям (jq.exe). На Linux - как есть.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# jq без MSYS-конвертации аргументов и без \r в выводе.
# Пути к файлам передавайте через native_path, входной JSON - через stdin.
jqx() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@" | sed 's/\r$//'; }

runtime_home() {
  case "$1" in
    claude) printf '%s' "$HOME/.claude" ;;
    codex)  printf '%s' "${CODEX_HOME:-$HOME/.codex}" ;;
    hermes) printf '%s' "${HERMES_HOME:-$HOME/.hermes}" ;;
    *) die "E_INTERNAL неизвестный рантайм: $1" ;;
  esac
}
```

- [ ] **Step 6: Написать `detect.sh`**

`overlay/lib/detect.sh`:

```bash
# Пререквизиты, профиль, обнаружение рантаймов.

check_prereqs() {
  if [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
     { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    die "E_PREREQ нужен bash >= 4.4, сейчас $BASH_VERSION"
  fi
  local c
  for c in diff sed awk find mktemp cmp; do
    command -v "$c" >/dev/null 2>&1 || die "E_PREREQ не найдена команда: $c"
  done
  command -v jq >/dev/null 2>&1 || die "E_PREREQ не найден jq. Установите: winget install jqlang.jq | sudo apt install jq | sudo pacman -S jq. На Windows после установки перезапустите терминал."
}

load_profile() {
  PROFILE_FILE="${HARNESS_PROFILE:-$OVERLAY_DIR/profile.env}"
  [ -f "$PROFILE_FILE" ] || die "E_PROFILE нет профиля: $PROFILE_FILE. Скопируйте overlay/profile.example.env в overlay/profile.env и заполните."
  RUNTIMES="claude codex hermes"
  WIKI_ENABLED=1
  WIKI_DIR=""
  AUTO_MEMORY_OFF=0
  MCP_OBSIDIAN=0
  DATAWEAVE_ENABLED=0
  DATAWEAVE_REPO=""
  RTK_ENABLED=0
  HOOK_COMMAND_STYLE=direct
  HOOK_BASH=""
  # shellcheck disable=SC1090
  source <(sed 's/\r$//' "$PROFILE_FILE")
  WIKI_DIR="${WIKI_DIR%/}"
  DATAWEAVE_REPO="${DATAWEAVE_REPO%/}"
}

validate_profile() {
  local k
  for k in WIKI_ENABLED AUTO_MEMORY_OFF MCP_OBSIDIAN DATAWEAVE_ENABLED RTK_ENABLED; do
    case "${!k}" in
      0|1) ;;
      *) die "E_PROFILE $k должен быть 0 или 1, сейчас: ${!k}" ;;
    esac
  done
  case "$HOOK_COMMAND_STYLE" in
    direct|explicit) ;;
    *) die "E_PROFILE HOOK_COMMAND_STYLE должен быть direct или explicit, сейчас: $HOOK_COMMAND_STYLE" ;;
  esac
  if [ "$HOOK_COMMAND_STYLE" = explicit ] && [ -z "$HOOK_BASH" ]; then
    die "E_PROFILE HOOK_COMMAND_STYLE=explicit требует HOOK_BASH"
  fi
  for k in WIKI_DIR DATAWEAVE_REPO HOOK_BASH; do
    case "${!k}" in
      *\\*) die "E_PROFILE $k: пишите путь с прямыми слэшами, сейчас: ${!k}" ;;
    esac
  done
  if [ "$WIKI_ENABLED" = 1 ]; then
    [ -n "$WIKI_DIR" ] || die "E_PROFILE WIKI_ENABLED=1 требует WIKI_DIR"
    [ -d "$WIKI_DIR" ] || die "E_WIKI_DIR нет папки вики: $WIKI_DIR. Создайте ее или выставьте WIKI_ENABLED=0."
  fi
  if [ "$DATAWEAVE_ENABLED" = 1 ] && [ -z "$DATAWEAVE_REPO" ]; then
    die "E_PROFILE DATAWEAVE_ENABLED=1 требует DATAWEAVE_REPO"
  fi
}

detect_runtimes() {
  ACTIVE_RUNTIMES=()
  local rt home
  for rt in $RUNTIMES; do
    case "$rt" in
      claude|codex|hermes) ;;
      *) die "E_PROFILE неизвестный рантайм в RUNTIMES: $rt" ;;
    esac
    home="$(runtime_home "$rt")"
    if [ -d "$home" ]; then
      ACTIVE_RUNTIMES+=("$rt")
      info "RUNTIME $rt: $home"
    else
      info "SKIP    runtime $rt: нет каталога $home"
    fi
  done
  [ "${#ACTIVE_RUNTIMES[@]}" -gt 0 ] || die "E_PREREQ не найден ни один рантайм из RUNTIMES: $RUNTIMES"
}

has_runtime() {
  local r
  for r in "${ACTIVE_RUNTIMES[@]}"; do
    if [ "$r" = "$1" ]; then return 0; fi
  done
  return 1
}
```

- [ ] **Step 7: Написать `harness.sh`**

`overlay/harness.sh`:

```bash
#!/usr/bin/env bash
# Личный харнес поверх KISA Stack.
# Использование: overlay/harness.sh [plan|apply]   (по умолчанию plan)
set -euo pipefail

OVERLAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$OVERLAY_DIR")"
UPSTREAM_DIR="${HARNESS_UPSTREAM_DIR:-$REPO_DIR}"
OVERLAY_SKILLS_DIR="${HARNESS_OVERLAY_SKILLS:-$OVERLAY_DIR/skills}"
OVERLAY_RULES_DIR="${HARNESS_OVERLAY_RULES:-$OVERLAY_DIR/rules}"
BUILD_DIR="${HARNESS_BUILD_DIR:-$OVERLAY_DIR/.build}"
RENDER_DIR="$BUILD_DIR/render"

for _lib in "$OVERLAY_DIR"/lib/*.sh; do
  # shellcheck disable=SC1090
  source "$_lib"
done

usage() { printf 'Usage: %s [plan|apply]\n' "$0" >&2; }

reset_build_dir() {
  case "$BUILD_DIR" in
    ""|"/"|"$HOME") die "E_INTERNAL опасный BUILD_DIR: '$BUILD_DIR'" ;;
  esac
  rm -rf "$BUILD_DIR"
  mkdir -p "$RENDER_DIR"
}

main() {
  local mode="${1:-plan}"
  case "$mode" in
    plan|apply) ;;
    *) usage; exit 2 ;;
  esac
  check_prereqs
  load_profile
  validate_profile
  detect_runtimes
  reset_build_dir
  info "режим: $mode"
  print_notes
}

main "$@"
```

Библиотеки только определяют функции и простые глобальные переменные, поэтому порядок их подключения (алфавитный, по glob) не важен. Следующие задачи добавляют файлы в `lib/` без правки этого цикла.

- [ ] **Step 8: Запустить тесты и убедиться, что они проходят**

Run: `bash overlay/tests/run.sh env`
Expected: 11 строк `... ok`, итог `passed: 11, failed: 0`, код возврата 0.

- [ ] **Step 9: Commit**

```bash
git add overlay/.gitignore overlay/.gitattributes overlay/profile.example.env \
        overlay/skills/.gitkeep overlay/rules overlay/lib/common.sh overlay/lib/detect.sh \
        overlay/harness.sh overlay/tests
git commit -m "Добавлен скелет слоя overlay: профиль, детект окружения, раннер тестов" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Управляемый блок

**Files:**
- Create: `overlay/lib/block.sh`
- Test: `overlay/tests/cases/block.sh`

**Interfaces:**
- Consumes: `die` из `common.sh`; `load_libs`, `fail`, `assert_*`, `SB` из `tests/run.sh`.
- Produces:
  - `marker_lines <file> <marker>` — номера строк, равных маркеру (хвостовой `\r` игнорируется), по одному на строку stdout.
  - `outside_block <file> <begin> <end>` — содержимое файла без блока и маркеров, в stdout.
  - `upsert_block <target> <content_file> <out_file> <begin> <end>` — пишет в `out_file` желаемое состояние `target`. `target` может не существовать или быть пустым. Непарные маркеры — `die E_MARKER`. `content_file` обязан заканчиваться переводом строки.

- [ ] **Step 1: Написать падающие тесты**

`overlay/tests/cases/block.sh`:

```bash
_BEG='<!-- kisa-harness:begin -->'
_END='<!-- kisa-harness:end -->'

test_block_new_file() {
  load_libs
  printf 'line A\n' > "$SB/c.md"
  ( upsert_block "$SB/absent.md" "$SB/c.md" "$SB/o.md" "$_BEG" "$_END" ) || fail "upsert упал"
  assert_eq "$(cat "$SB/o.md")" "$_BEG"$'\n''line A'$'\n'"$_END"
}

test_block_append_preserves_bytes() {
  load_libs
  printf 'line A\n' > "$SB/c.md"
  printf '# gstack\nmine' > "$SB/t.md"          # без перевода строки в конце
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o.md" "$_BEG" "$_END" ) || fail "upsert упал"
  head -c "$(wc -c < "$SB/t.md")" "$SB/o.md" | cmp -s - "$SB/t.md" || fail "чужие байты изменены"
  assert_contains "$SB/o.md" "$_BEG"
  assert_contains "$SB/o.md" 'line A'
}

test_block_idempotent() {
  load_libs
  printf 'line A\n' > "$SB/c.md"
  printf '# gstack\n' > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o1.md" "$_BEG" "$_END" ) || fail "первый upsert упал"
  ( upsert_block "$SB/o1.md" "$SB/c.md" "$SB/o2.md" "$_BEG" "$_END" ) || fail "второй upsert упал"
  cmp -s "$SB/o1.md" "$SB/o2.md" || fail "повторный upsert изменил файл"
}

test_block_replace_keeps_outside() {
  load_libs
  printf 'OLD\n' > "$SB/c1.md"
  printf 'NEW\n' > "$SB/c2.md"
  printf 'before\n' > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c1.md" "$SB/o1.md" "$_BEG" "$_END" ) || fail "upsert упал"
  printf 'after\n' >> "$SB/o1.md"
  ( upsert_block "$SB/o1.md" "$SB/c2.md" "$SB/o2.md" "$_BEG" "$_END" ) || fail "замена упала"
  assert_contains "$SB/o2.md" 'before'
  assert_contains "$SB/o2.md" 'after'
  assert_contains "$SB/o2.md" 'NEW'
  assert_not_contains "$SB/o2.md" 'OLD'
}

test_block_crlf_markers() {
  load_libs
  printf 'X\n' > "$SB/c.md"
  printf 'top\n' > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o1.md" "$_BEG" "$_END" ) || fail "upsert упал"
  sed 's/$/\r/' "$SB/o1.md" > "$SB/crlf.md"     # редактор перевел файл в CRLF
  ( upsert_block "$SB/crlf.md" "$SB/c.md" "$SB/o2.md" "$_BEG" "$_END" ) || fail "upsert на CRLF упал"
  assert_eq "$(grep -c 'kisa-harness:begin' "$SB/o2.md")" 1
}

test_block_unpaired_marker() {
  load_libs
  printf 'X\n' > "$SB/c.md"
  printf '%s\nsomething\n' "$_BEG" > "$SB/t.md"
  ( upsert_block "$SB/t.md" "$SB/c.md" "$SB/o.md" "$_BEG" "$_END" ) > "$SB/out.log" 2>&1 \
    && fail "непарный маркер должен давать ошибку"
  assert_contains "$SB/out.log" E_MARKER
}

test_block_outside_block() {
  load_libs
  printf 'a\n# >>> kisa-harness >>>\n[mcp_servers.deploychan]\n# <<< kisa-harness <<<\nb\n' > "$SB/t.toml"
  assert_eq "$(outside_block "$SB/t.toml" '# >>> kisa-harness >>>' '# <<< kisa-harness <<<')" 'a'$'\n''b'
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh block`
Expected: 7 FAIL с `upsert_block: command not found` / `outside_block: command not found`.

- [ ] **Step 3: Написать `block.sh`**

`overlay/lib/block.sh`:

```bash
# Управляемый блок: харнес владеет только текстом между своими маркерами.

# Номера строк, равных маркеру. Хвостовой \r игнорируется: редактор мог
# перевести файл в CRLF, и без этого мы бы дописали второй блок.
marker_lines() {
  M="$2" awk '{ l = $0; sub(/\r$/, "", l); if (l == ENVIRON["M"]) print NR }' "$1"
}

# Содержимое файла без управляемого блока и его маркеров.
outside_block() {
  B="$2" E="$3" awk '
    { l = $0; sub(/\r$/, "", l) }
    l == ENVIRON["B"] { skip = 1 }
    !skip { print }
    l == ENVIRON["E"] { skip = 0 }
  ' "$1"
}

# upsert_block <target> <content_file> <out_file> <begin> <end>
upsert_block() {
  local target="$1" content="$2" out="$3" begin="$4" end="$5" nb ne b e
  mkdir -p "$(dirname "$out")"

  if [ ! -s "$target" ]; then
    { printf '%s\n' "$begin"; cat "$content"; printf '%s\n' "$end"; } > "$out"
    return 0
  fi

  nb="$(marker_lines "$target" "$begin" | wc -l | tr -d ' ')"
  ne="$(marker_lines "$target" "$end" | wc -l | tr -d ' ')"

  if [ "$nb" = 0 ] && [ "$ne" = 0 ]; then
    {
      cat "$target"
      [ -z "$(tail -c1 "$target")" ] || printf '\n'
      printf '\n%s\n' "$begin"; cat "$content"; printf '%s\n' "$end"
    } > "$out"
    return 0
  fi

  if [ "$nb" != 1 ] || [ "$ne" != 1 ]; then
    die "E_MARKER в $target непарные маркеры ($begin: $nb, $end: $ne). Исправьте файл вручную."
  fi
  b="$(marker_lines "$target" "$begin")"
  e="$(marker_lines "$target" "$end")"
  [ "$b" -lt "$e" ] || die "E_MARKER в $target маркер конца стоит раньше маркера начала."

  {
    head -n "$((b - 1))" "$target"
    printf '%s\n' "$begin"; cat "$content"; printf '%s\n' "$end"
    tail -n "+$((e + 1))" "$target"
  } > "$out"
}
```

`head`/`tail` по номерам строк вместо awk — чтобы содержимое вне маркеров копировалось побайтно, включая CRLF и отсутствие перевода строки в конце.

- [ ] **Step 4: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh block`
Expected: `passed: 7, failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add overlay/lib/block.sh overlay/tests/cases/block.sh
git commit -m "Добавлен управляемый блок: вставка и замена между маркерами" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Рендеринг правил

**Files:**
- Create: `overlay/lib/render.sh`
- Test: `overlay/tests/cases/render.sh`

**Interfaces:**
- Consumes: `die` из `common.sh`; переменные профиля `WIKI_ENABLED`, `WIKI_DIR`, `AUTO_MEMORY_OFF`, `MCP_OBSIDIAN`, `DATAWEAVE_ENABLED`, `DATAWEAVE_REPO`, `RTK_ENABLED`.
- Produces: `render_rules <claude|agents> <template> <extra_file_or_empty> <out_file>`. Результат заканчивается переводом строки, не содержит HTML-комментариев и плейсхолдеров. Ошибки: `E_ANCHOR`, `E_PLACEHOLDER` (процесс завершается, вызывать в подоболочке, если нужно перехватить).

Якоря (точные строки шаблонов апстрима на коммите `63c6f6b`):

| Флаг = 0 | CLAUDE.md | AGENTS.md |
|---|---|---|
| `WIKI_ENABLED` | от строки `# LLM Wiki` до конца | от `# Память и LLM Wiki` до строки перед `# Skills` |
| `AUTO_MEMORY_OFF` | от `## Память` до строки перед `## ObsidianDataWeave` | — |
| `MCP_OBSIDIAN` | строка с префиксом `**Проверка структуры vault` | — |
| `DATAWEAVE_ENABLED` | от `## ObsidianDataWeave` до конца | пункт с префиксом `- Предпочитай пайплайн ObsidianDataWeave:` и его строки с отступом |
| `RTK_ENABLED` | — | пункт с префиксом `- Для шумных команд предпочитай` и его строки с отступом |

При `WIKI_ENABLED=0` вложенные в вики-секцию вырезки не выполняются: их якорей уже нет.

- [ ] **Step 1: Написать падающие тесты**

`overlay/tests/cases/render.sh`:

```bash
_render_defaults() {
  WIKI_ENABLED=1; WIKI_DIR="$SB/wiki"; AUTO_MEMORY_OFF=0; MCP_OBSIDIAN=0
  DATAWEAVE_ENABLED=0; DATAWEAVE_REPO=""; RTK_ENABLED=0
}
_CLAUDE_TPL() { printf '%s' "$REPO_DIR/global-config/CLAUDE.md"; }
_AGENTS_TPL() { printf '%s' "$REPO_DIR/global-config/AGENTS.md"; }

test_render_claude_defaults() {
  load_libs; _render_defaults
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_eq "$(head -n1 "$SB/o.md")" '# Кто ты'
  assert_contains "$SB/o.md" '# LLM Wiki'
  assert_contains "$SB/o.md" "$SB/wiki/claude-code/"
  assert_contains "$SB/o.md" '<проект-2>'
  assert_not_contains "$SB/o.md" '<!--'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
  assert_not_contains "$SB/o.md" '## Память'
  assert_not_contains "$SB/o.md" '## ObsidianDataWeave'
  assert_not_contains "$SB/o.md" 'Проверка структуры vault'
}

test_render_claude_wiki_off() {
  load_libs; _render_defaults; WIKI_ENABLED=0
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_not_contains "$SB/o.md" '# LLM Wiki'
  assert_contains "$SB/o.md" '# Скиллы и инструменты'
  [ "$(tail -n1 "$SB/o.md")" != '---' ] || fail "в конце остался повисший разделитель"
}

test_render_claude_all_on() {
  load_libs; _render_defaults
  AUTO_MEMORY_OFF=1; MCP_OBSIDIAN=1; DATAWEAVE_ENABLED=1; DATAWEAVE_REPO="C:/src"
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_contains "$SB/o.md" '## Память'
  assert_contains "$SB/o.md" 'Проверка структуры vault'
  assert_contains "$SB/o.md" 'C:/src/ObsidianDataWeave'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
}

test_render_agents_defaults() {
  load_libs; _render_defaults
  ( render_rules agents "$(_AGENTS_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_contains "$SB/o.md" '# Память и LLM Wiki'
  assert_contains "$SB/o.md" "$SB/wiki/codex/pages/overview.md"
  assert_contains "$SB/o.md" '# Skills'
  assert_not_contains "$SB/o.md" 'Для шумных команд предпочитай'
  assert_not_contains "$SB/o.md" 'Предпочитай пайплайн ObsidianDataWeave'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
  assert_not_contains "$SB/o.md" '<!--'
}

test_render_agents_wiki_off() {
  load_libs; _render_defaults; WIKI_ENABLED=0
  ( render_rules agents "$(_AGENTS_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_not_contains "$SB/o.md" '# Память и LLM Wiki'
  assert_contains "$SB/o.md" '# Skills'
  assert_not_contains "$SB/o.md" 'ПУТЬ_К'
}

test_render_path_with_ampersand() {
  load_libs; _render_defaults; WIKI_DIR='C:/Users/me/My & Wiki'
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/o.md" ) || fail "рендер упал"
  assert_contains "$SB/o.md" 'C:/Users/me/My & Wiki/claude-code/'
}

test_render_crlf_template_same_result() {
  load_libs; _render_defaults
  sed 's/$/\r/' "$(_CLAUDE_TPL)" > "$SB/CLAUDE.md"
  ( render_rules claude "$(_CLAUDE_TPL)" "" "$SB/lf.md" ) || fail "рендер LF упал"
  ( render_rules claude "$SB/CLAUDE.md" "" "$SB/crlf.md" ) || fail "рендер CRLF упал"
  cmp -s "$SB/lf.md" "$SB/crlf.md" || fail "CRLF-шаблон дал другой результат"
}

test_render_extra_appended() {
  load_libs; _render_defaults
  printf 'MY-OVERLAY-RULE' > "$SB/extra.md"      # без перевода строки в конце
  ( render_rules claude "$(_CLAUDE_TPL)" "$SB/extra.md" "$SB/o.md" ) || fail "рендер упал"
  assert_eq "$(tail -n1 "$SB/o.md")" 'MY-OVERLAY-RULE'
  [ -z "$(tail -c1 "$SB/o.md")" ] || fail "результат не заканчивается переводом строки"
}

test_render_missing_anchor_fails() {
  load_libs; _render_defaults; WIKI_ENABLED=0
  printf '# Кто ты\n\nтекст без вики-секции\n' > "$SB/t.md"
  ( render_rules claude "$SB/t.md" "" "$SB/o.md" ) > "$SB/out.log" 2>&1 \
    && fail "шаблон без якоря должен давать ошибку"
  assert_contains "$SB/out.log" E_ANCHOR
}

test_render_leftover_placeholder_fails() {
  load_libs; _render_defaults
  AUTO_MEMORY_OFF=1; MCP_OBSIDIAN=1; DATAWEAVE_ENABLED=1; DATAWEAVE_REPO="C:/src"
  printf '# LLM Wiki\n\nпуть: <ПУТЬ_К_ЧЕМУ_ТО>\n' > "$SB/t.md"
  ( render_rules claude "$SB/t.md" "" "$SB/o.md" ) > "$SB/out.log" 2>&1 \
    && fail "недозамененный плейсхолдер должен давать ошибку"
  assert_contains "$SB/out.log" E_PLACEHOLDER
}
```

Тесты `*_defaults`, `*_wiki_off`, `*_all_on` работают на настоящих шаблонах апстрима. Это намеренно: после `git pull upstream` они первыми покажут, что Киса переименовала заголовок-якорь.

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh render`
Expected: 10 FAIL с `render_rules: command not found`.

- [ ] **Step 3: Написать `render.sh`**

`overlay/lib/render.sh`:

```bash
# Рендеринг правил из шаблонов апстрима.
# Якоря - заголовки и начала пунктов. Не найден якорь или остался плейсхолдер -
# падаем громко: остановленная установка лучше молча испорченных правил.

RENDER_LABEL=""

strip_html_comments() {
  awk '{
    line = $0; out = ""; touched = in_c
    while (line != "") {
      if (in_c) {
        e = index(line, "-->")
        if (e == 0) { line = "" } else { line = substr(line, e + 3); in_c = 0 }
      } else {
        s = index(line, "<!--")
        if (s == 0) { out = out line; line = "" }
        else { touched = 1; out = out substr(line, 1, s - 1); line = substr(line, s + 4); in_c = 1 }
      }
    }
    if (touched && out ~ /^[ \t]*$/) next
    print out
  }'
}

squeeze_blank() { awk 'NF == 0 { b++; if (b > 1) next } NF > 0 { b = 0 } { print }'; }

# Убрать пустые строки в начале, пустые строки и повисшие "---" в конце.
trim_edges() {
  awk '{ l[NR] = $0 }
    END {
      s = 1; while (s <= NR && l[s] ~ /^[ \t]*$/) s++
      n = NR; while (n >= s && (l[n] ~ /^[ \t]*$/ || l[n] == "---")) n--
      for (i = s; i <= n; i++) print l[i]
    }'
}

_finish_cut() {
  if [ "$1" -ne 0 ]; then rm -f "$2.tmp"; exit 1; fi
  mv "$2.tmp" "$2"
}

# cut_to_eof <file> <anchor>: удалить от строки, равной anchor, до конца файла.
cut_to_eof() {
  local rc=0
  A="$2" L="$RENDER_LABEL" awk '
    $0 == ENVIRON["A"] { found = 1 }
    !found { print }
    END { if (!found) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 } }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# cut_until <file> <anchor> <stop>: удалить от anchor до строки перед stop.
cut_until() {
  local rc=0
  A="$2" B="$3" L="$RENDER_LABEL" awk '
    !fa && $0 == ENVIRON["A"] { fa = 1; skip = 1 }
    skip && $0 == ENVIRON["B"] { fb = 1; skip = 0 }
    !skip { print }
    END {
      if (!fa) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 }
      if (!fb) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["B"] > "/dev/stderr"; exit 3 }
    }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# cut_line <file> <prefix>: удалить строки, начинающиеся с prefix.
cut_line() {
  local rc=0
  A="$2" L="$RENDER_LABEL" awk '
    index($0, ENVIRON["A"]) == 1 { found = 1; next }
    { print }
    END { if (!found) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 } }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# cut_bullet <file> <prefix>: удалить пункт списка и его строки с отступом 2+ пробела.
cut_bullet() {
  local rc=0
  A="$2" L="$RENDER_LABEL" awk '
    skip && /^  / { next }
    { skip = 0 }
    index($0, ENVIRON["A"]) == 1 { found = 1; skip = 1; next }
    { print }
    END { if (!found) { printf "[harness] E_ANCHOR в %s не найден якорь: %s\n", ENVIRON["L"], ENVIRON["A"] > "/dev/stderr"; exit 3 } }
  ' "$1" > "$1.tmp" || rc=$?
  _finish_cut "$rc" "$1"
}

# Буквальная замена: в путях бывают & и другие символы, особые для sed и gsub.
replace_literal() {
  FROM="$2" TO="$3" awk '{
    s = $0; out = ""; n = length(ENVIRON["FROM"])
    while ((i = index(s, ENVIRON["FROM"])) > 0) {
      out = out substr(s, 1, i - 1) ENVIRON["TO"]
      s = substr(s, i + n)
    }
    print out s
  }' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

# Плейсхолдер апстрима - токен <...> без пробелов с подчеркиванием внутри.
# Иллюстративные <проект-2> и <project> под правило не попадают.
check_placeholders() {
  local hits
  hits="$(grep -nE '<[^<> ]*_[^<> ]*>' "$1" || true)"
  [ -z "$hits" ] || die "E_PLACEHOLDER в $RENDER_LABEL остались плейсхолдеры:"$'\n'"$hits"
}

# render_rules <claude|agents> <template> <extra_file_or_empty> <out_file>
render_rules() {
  local kind="$1" template="$2" extra="$3" out="$4" work
  RENDER_LABEL="$(basename "$template")"
  mkdir -p "$(dirname "$out")"
  work="$out.work"
  sed 's/\r$//' "$template" | strip_html_comments > "$work"

  if [ "$kind" = claude ]; then
    if [ "$WIKI_ENABLED" = 0 ]; then
      cut_to_eof "$work" '# LLM Wiki'
    else
      [ "$MCP_OBSIDIAN" = 1 ]      || cut_line   "$work" '**Проверка структуры vault'
      [ "$AUTO_MEMORY_OFF" = 1 ]   || cut_until  "$work" '## Память' '## ObsidianDataWeave'
      [ "$DATAWEAVE_ENABLED" = 1 ] || cut_to_eof "$work" '## ObsidianDataWeave'
    fi
  else
    [ "$RTK_ENABLED" = 1 ] || cut_bullet "$work" '- Для шумных команд предпочитай'
    if [ "$WIKI_ENABLED" = 0 ]; then
      cut_until "$work" '# Память и LLM Wiki' '# Skills'
    else
      [ "$DATAWEAVE_ENABLED" = 1 ] || cut_bullet "$work" '- Предпочитай пайплайн ObsidianDataWeave:'
    fi
  fi

  if [ "$WIKI_ENABLED" = 1 ]; then
    replace_literal "$work" '<ПУТЬ_К_VAULT>/LLM Wiki' "$WIKI_DIR"
  fi
  if [ "$DATAWEAVE_ENABLED" = 1 ]; then
    replace_literal "$work" '<ПУТЬ_К_КЛОНУ>' "$DATAWEAVE_REPO"
  fi
  check_placeholders "$work"

  {
    squeeze_blank < "$work" | trim_edges
    if [ -n "$extra" ] && [ -s "$extra" ]; then
      printf '\n'
      sed 's/\r$//' "$extra"
      [ -z "$(tail -c1 "$extra")" ] || printf '\n'
    fi
  } > "$out"
  rm -f "$work"
}
```

Порядок вырезок в CLAUDE.md важен: `cut_until '## Память' '## ObsidianDataWeave'` использует заголовок ObsidianDataWeave как стоп-якорь, поэтому идет раньше вырезки самого раздела ObsidianDataWeave.

- [ ] **Step 4: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh render`
Expected: `passed: 10, failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add overlay/lib/render.sh overlay/tests/cases/render.sh
git commit -m "Добавлен рендеринг правил из шаблонов апстрима с громким падением на якорях" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Реестр записей, бэкапы, установка правил

**Files:**
- Create: `overlay/lib/pending.sh`, `overlay/lib/backup.sh`, `overlay/lib/rules.sh`
- Modify: `overlay/harness.sh` (функция `main`)
- Test: `overlay/tests/cases/rules.sh`

**Interfaces:**
- Consumes: `render_rules` (Task 3), `upsert_block` (Task 2), `runtime_home`, `info`, `die` (Task 1), переменные `RENDER_DIR`, `UPSTREAM_DIR`, `OVERLAY_RULES_DIR`.
- Produces:
  - `pending.sh`: `propose_file <src> <dst> [644|755]`, `show_pending` (печатает `NEW`/`SAME`/`CHANGED` и `diff -u`, выставляет `CHANGED_COUNT`), `commit_pending` (бэкап + запись измененных).
  - `backup.sh`: переменная `HARNESS_TS`, `backup_dir` (stdout: `$HOME/.kisa-harness/backups/$HARNESS_TS`), `backup_file <path>`.
  - `rules.sh`: `plan_rules <rt>` — для `claude` и `codex` рендерит правила и предлагает запись; для `hermes` ничего не делает.

- [ ] **Step 1: Написать падающие тесты**

`overlay/tests/cases/rules.sh`:

```bash
_BEGIN_MARK='<!-- kisa-harness:begin -->'
_END_MARK='<!-- kisa-harness:end -->'

test_rules_created() {
  run_ok apply
  assert_contains "$HOME/.claude/CLAUDE.md" "$_BEGIN_MARK"
  assert_contains "$HOME/.claude/CLAUDE.md" '# Кто ты'
  assert_contains "$HOME/.claude/CLAUDE.md" "$SB/wiki/claude-code/"
  assert_contains "$CODEX_HOME/AGENTS.md" "$_END_MARK"
  assert_no_path "$HERMES_HOME/AGENTS.md"
  assert_no_path "$HERMES_HOME/CLAUDE.md"
}

test_rules_foreign_content_preserved() {
  printf '# gstack\n\nmy own block\n' > "$HOME/.claude/CLAUDE.md"
  cp "$HOME/.claude/CLAUDE.md" "$SB/orig.md"
  run_ok apply
  head -c "$(wc -c < "$SB/orig.md")" "$HOME/.claude/CLAUDE.md" | cmp -s - "$SB/orig.md" \
    || fail "чужое содержимое CLAUDE.md изменено"
  assert_contains "$HOME/.claude/CLAUDE.md" "$_BEGIN_MARK"
  assert_file "$HOME/.kisa-harness/backups/20260101-000000/.claude/CLAUDE.md"
  cmp -s "$HOME/.kisa-harness/backups/20260101-000000/.claude/CLAUDE.md" "$SB/orig.md" \
    || fail "бэкап не совпадает с оригиналом"
}

test_rules_plan_writes_nothing() {
  printf 'x\n' > "$HOME/.claude/CLAUDE.md"
  local home_before repo_before
  home_before="$(tree_hash "$HOME")"
  repo_before="$(git -C "$REPO_DIR" status --porcelain)"
  run_ok plan
  assert_eq "$(tree_hash "$HOME")" "$home_before"
  assert_eq "$(git -C "$REPO_DIR" status --porcelain)" "$repo_before"
  assert_contains "$SB/out.log" 'CHANGED'
}

test_rules_idempotent() {
  run_ok apply
  local before; before="$(tree_hash "$HOME")"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(tree_hash "$HOME")" "$before"
  assert_no_path "$HOME/.kisa-harness/backups/20260101-000001"
}

test_rules_unpaired_marker_stops_before_any_write() {
  printf '%s\nbroken\n' "$_BEGIN_MARK" > "$HOME/.claude/CLAUDE.md"
  local before; before="$(tree_hash "$HOME")"
  run_fail E_MARKER apply
  assert_eq "$(tree_hash "$HOME")" "$before"
}

test_rules_wiki_off() {
  write_profile 'WIKI_ENABLED=0'
  run_ok apply
  assert_not_contains "$HOME/.claude/CLAUDE.md" '# LLM Wiki'
  assert_not_contains "$CODEX_HOME/AGENTS.md" '# Память и LLM Wiki'
}

test_rules_overlay_extra() {
  printf 'MY-OVERLAY-RULE\n' > "$HARNESS_OVERLAY_RULES/claude.md"
  run_ok apply
  assert_contains "$HOME/.claude/CLAUDE.md" 'MY-OVERLAY-RULE'
  assert_not_contains "$CODEX_HOME/AGENTS.md" 'MY-OVERLAY-RULE'
}

test_rules_block_updates_in_place() {
  run_ok apply
  printf 'tail added by user\n' >> "$HOME/.claude/CLAUDE.md"
  printf 'SECOND-VERSION\n' > "$HARNESS_OVERLAY_RULES/claude.md"
  export HARNESS_TS="20260101-000002"
  run_ok apply
  assert_contains "$HOME/.claude/CLAUDE.md" 'SECOND-VERSION'
  assert_contains "$HOME/.claude/CLAUDE.md" 'tail added by user'
  assert_eq "$(grep -c 'kisa-harness:begin' "$HOME/.claude/CLAUDE.md")" 1
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh rules`
Expected: 8 FAIL (файлы правил не создаются: `main` пока ничего не ставит).

- [ ] **Step 3: Написать `backup.sh`**

`overlay/lib/backup.sh`:

```bash
# Бэкапы. Один запуск - один каталог ~/.kisa-harness/backups/<timestamp>/
# с зеркалом путей от $HOME. Каталог создается только при первой записи.

HARNESS_TS="${HARNESS_TS:-$(date +%Y%m%d-%H%M%S)}"

backup_dir() { printf '%s' "$HOME/.kisa-harness/backups/$HARNESS_TS"; }

backup_file() {
  local path="$1" rel dest
  [ -e "$path" ] || return 0
  case "$path" in
    "$HOME"/*) rel="${path#"$HOME"/}" ;;
    *) rel="_abs/$(printf '%s' "$path" | sed 's|^/||; s|:||g')" ;;
  esac
  dest="$(backup_dir)/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -p "$path" "$dest"
  info "BACKUP  $path -> $dest"
}
```

- [ ] **Step 4: Написать `pending.sh`**

`overlay/lib/pending.sh`:

```bash
# Реестр предложенных записей. plan и apply проходят один путь: шаги готовят
# желаемое содержимое в .build/render/ и регистрируют его здесь. plan только
# показывает диффы, apply после показа делает бэкап и пишет.

PENDING_SRC=()
PENDING_DST=()
PENDING_MODE=()
CHANGED_COUNT=0

propose_file() {
  PENDING_SRC+=("$1")
  PENDING_DST+=("$2")
  PENDING_MODE+=("${3:-644}")
}

show_pending() {
  local i src dst
  CHANGED_COUNT=0
  for i in "${!PENDING_SRC[@]}"; do
    src="${PENDING_SRC[$i]}"; dst="${PENDING_DST[$i]}"
    if [ ! -e "$dst" ]; then
      info "NEW     $dst"
      diff -u /dev/null "$src" || true
      CHANGED_COUNT=$((CHANGED_COUNT + 1))
    elif cmp -s "$src" "$dst"; then
      info "SAME    $dst"
    else
      info "CHANGED $dst"
      diff -u "$dst" "$src" || true
      CHANGED_COUNT=$((CHANGED_COUNT + 1))
    fi
  done
}

commit_pending() {
  local i src dst mode
  for i in "${!PENDING_SRC[@]}"; do
    src="${PENDING_SRC[$i]}"; dst="${PENDING_DST[$i]}"; mode="${PENDING_MODE[$i]}"
    if [ -e "$dst" ] && cmp -s "$src" "$dst"; then continue; fi
    backup_file "$dst"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    if [ "$mode" = 755 ]; then chmod 755 "$dst"; fi
    info "WROTE   $dst"
  done
}
```

`chmod` делается только для `755`: `cp` поверх существующего файла сохраняет его права, и ужесточенные пользователем права на `settings.json` не должны ослабляться.

- [ ] **Step 5: Написать `rules.sh`**

`overlay/lib/rules.sh`:

```bash
# Установка правил: рендер шаблона апстрима + личный блок -> управляемый блок
# в CLAUDE.md (Claude Code) и AGENTS.md (Codex). Для Hermes апстрим правил не дает.

RULES_BEGIN='<!-- kisa-harness:begin -->'
RULES_END='<!-- kisa-harness:end -->'

plan_rules() {
  local rt="$1" kind template extra target block out
  case "$rt" in
    claude)
      kind=claude
      template="$UPSTREAM_DIR/global-config/CLAUDE.md"
      extra="$OVERLAY_RULES_DIR/claude.md"
      target="$(runtime_home claude)/CLAUDE.md"
      ;;
    codex)
      kind=agents
      template="$UPSTREAM_DIR/global-config/AGENTS.md"
      extra="$OVERLAY_RULES_DIR/agents.md"
      target="$(runtime_home codex)/AGENTS.md"
      ;;
    *) return 0 ;;
  esac
  [ -f "$template" ] || die "E_ANCHOR нет шаблона апстрима: $template"
  block="$RENDER_DIR/$rt/rules.block.md"
  out="$RENDER_DIR/$rt/$(basename "$target")"
  render_rules "$kind" "$template" "$extra" "$block"
  upsert_block "$target" "$block" "$out" "$RULES_BEGIN" "$RULES_END"
  propose_file "$out" "$target"
}
```

- [ ] **Step 6: Подключить шаги в `harness.sh`**

В `overlay/harness.sh` заменить функцию `main` целиком на:

```bash
main() {
  local mode="${1:-plan}" rt
  case "$mode" in
    plan|apply) ;;
    *) usage; exit 2 ;;
  esac
  check_prereqs
  load_profile
  validate_profile
  detect_runtimes
  reset_build_dir
  info "режим: $mode"

  for rt in "${ACTIVE_RUNTIMES[@]}"; do
    plan_rules "$rt"
  done

  show_pending
  if [ "$mode" = apply ]; then
    commit_pending
  else
    info "это был plan: ничего не записано. Применить: overlay/harness.sh apply"
  fi
  print_notes
}
```

Все ошибки рендеринга и маркеров возникают в цикле `plan_*`, то есть до `commit_pending` — до первой записи.

- [ ] **Step 7: Запустить все тесты**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 36, failed: 0` (11 env + 7 block + 10 render + 8 rules).

- [ ] **Step 8: Commit**

```bash
git add overlay/lib/pending.sh overlay/lib/backup.sh overlay/lib/rules.sh \
        overlay/harness.sh overlay/tests/cases/rules.sh
git commit -m "Добавлена установка правил: plan с диффами, apply с бэкапами" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Скиллы через стейджинг вокруг install.sh

**Files:**
- Create: `overlay/lib/stage.sh`
- Modify: `overlay/lib/backup.sh` (добавить `list_skill_backups`), `overlay/harness.sh` (функция `main`)
- Test: `overlay/tests/cases/skills.sh`

**Interfaces:**
- Consumes: `runtime_home`, `copy_lf`, `info` (Task 1); `backup_dir` (Task 4); переменные `BUILD_DIR`, `UPSTREAM_DIR`, `OVERLAY_SKILLS_DIR`.
- Produces:
  - `backup.sh`: `list_skill_backups <rt>` — пути папок `*.backup-*` в каталоге скиллов рантайма, по одному на строку.
  - `stage.sh`: `plan_skills <rt>` (печатает `SKILL   <rt>/<name>: new|changed|same`, собирает стейджинг, заполняет ассоциативный массив `SKILL_STAGED[rt]`), `apply_skills <rt>` (запускает `install.sh` из стейджинга, возвращает файлы `.env`, переносит backup-папки этого запуска).

Поведение `install.sh` апстрима, на которое опирается задача (проверено чтением файла): корень репо он вычисляет от собственного расположения (`BASH_SOURCE`), скиллы берет из соседней папки `skills/`, цель — `$HOME/.claude/skills`, `${CODEX_HOME:-$HOME/.codex}/skills`, `${HERMES_HOME:-$HOME/.hermes}/skills`; существующий скилл переименовывает в `<name>.backup-<YYYYmmdd-HHMMSS>` рядом и копирует новый через `cp -a`.

Два решения сверх буквы спека, оба — следствие инварианта «никакой слепой перезаписи»:

1. Скилл считается измененным, только если отличается или отсутствует файл **из источника**. Лишние файлы в установленной копии (например, `.env` с ключом EvoLink в `suno-music`, который README апстрима велит класть рядом со скриптами) изменением не считаются, иначе каждый запуск переустанавливал бы скилл и уносил ключ в бэкап.
2. При настоящем обновлении скилла файлы с именем `.env` из прежней копии возвращаются в новую.

- [ ] **Step 1: Написать падающие тесты**

`overlay/tests/cases/skills.sh`:

```bash
test_skills_clean_install() {
  run_ok apply
  local root
  for root in "$HOME/.claude" "$CODEX_HOME" "$HERMES_HOME"; do
    assert_file "$root/skills/researcher/SKILL.md"
    assert_file "$root/skills/suno-music/generate.py"
    assert_file "$root/skills/css-graphics/scripts/render.js"
  done
}

test_skills_plan_installs_nothing() {
  run_ok plan
  assert_no_path "$HOME/.claude/skills"
  assert_contains "$SB/out.log" 'SKILL   claude/researcher: new'
}

test_skills_second_run_is_noop() {
  run_ok apply
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_contains "$SB/out.log" 'SKILL   claude/researcher: same'
  assert_no_path "$HOME/.kisa-harness/backups/20260101-000001"
  assert_eq "$(find "$HOME/.claude/skills" -maxdepth 1 -name '*.backup-*' | wc -l | tr -d ' ')" 0
}

test_skills_overlay_wins() {
  mkdir -p "$HARNESS_OVERLAY_SKILLS/researcher"
  printf -- '---\nname: researcher\ndescription: overlay version\n---\nOVERLAY-MARK\n' \
    > "$HARNESS_OVERLAY_SKILLS/researcher/SKILL.md"
  run_ok apply
  assert_contains "$HOME/.claude/skills/researcher/SKILL.md" 'OVERLAY-MARK'
  assert_contains "$SB/out.log" 'SKILL   claude/researcher: new (overlay)'
}

test_skills_overlay_only_skill_installed() {
  mkdir -p "$HARNESS_OVERLAY_SKILLS/my-own"
  printf -- '---\nname: my-own\ndescription: mine\n---\nbody\n' > "$HARNESS_OVERLAY_SKILLS/my-own/SKILL.md"
  run_ok apply
  assert_file "$CODEX_HOME/skills/my-own/SKILL.md"
}

test_skills_extra_file_is_not_a_change() {
  run_ok apply
  printf 'KEY=secret\n' > "$HOME/.claude/skills/suno-music/.env"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_contains "$SB/out.log" 'SKILL   claude/suno-music: same'
  assert_contains "$HOME/.claude/skills/suno-music/.env" 'KEY=secret'
}

test_skills_update_sweeps_backup_and_keeps_env() {
  run_ok apply
  printf 'KEY=secret\n' > "$HOME/.claude/skills/suno-music/.env"
  printf 'local edit\n' >> "$HOME/.claude/skills/suno-music/SKILL.md"
  export HARNESS_TS="20260101-000002"
  run_ok apply
  assert_contains "$SB/out.log" 'SKILL   claude/suno-music: changed'
  assert_not_contains "$HOME/.claude/skills/suno-music/SKILL.md" 'local edit'
  assert_contains "$HOME/.claude/skills/suno-music/.env" 'KEY=secret'
  assert_eq "$(find "$HOME/.claude/skills" -maxdepth 1 -name '*.backup-*' | wc -l | tr -d ' ')" 0
  local kept
  kept="$(find "$HOME/.kisa-harness/backups/20260101-000002/skills/claude" -path '*suno-music.backup-*' -name SKILL.md)"
  [ -n "$kept" ] || fail "прежняя версия скилла не перенесена в бэкапы"
  assert_contains "$kept" 'local edit'
}

test_skills_foreign_backup_dir_untouched() {
  mkdir -p "$HOME/.claude/skills/old.backup-20250101-000000"
  printf 'x\n' > "$HOME/.claude/skills/old.backup-20250101-000000/SKILL.md"
  run_ok apply
  assert_file "$HOME/.claude/skills/old.backup-20250101-000000/SKILL.md"
}

test_skills_runtime_without_home_skipped() {
  rm -rf "$HERMES_HOME"
  run_ok apply
  assert_no_path "$HERMES_HOME"
  assert_file "$HOME/.claude/skills/researcher/SKILL.md"
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh skills`
Expected: 9 FAIL (скиллы не ставятся).

- [ ] **Step 3: Добавить `list_skill_backups` в `backup.sh`**

Дописать в конец `overlay/lib/backup.sh`:

```bash

# Папки вида <skill>.backup-<timestamp>, которые install.sh апстрима оставляет
# прямо в каталоге скиллов рантайма.
list_skill_backups() {
  local root d
  root="$(runtime_home "$1")/skills"
  [ -d "$root" ] || return 0
  for d in "$root"/*.backup-*; do
    if [ -d "$d" ]; then printf '%s\n' "$d"; fi
  done
  return 0
}
```

- [ ] **Step 4: Написать `stage.sh`**

`overlay/lib/stage.sh`:

```bash
# Скиллы: стейджинг вокруг install.sh апстрима.
# install.sh ставит все из папки skills/ рядом с собой, поэтому мы собираем
# .build/stage/<rt>/{install.sh,skills/} только из новых и измененных скиллов
# и запускаем его оттуда. Сам install.sh не правится.

declare -gA SKILL_STAGED=()

skill_names() {
  local d
  {
    for d in "$UPSTREAM_DIR/skills"/*/ "$OVERLAY_SKILLS_DIR"/*/; do
      if [ -f "${d}SKILL.md" ]; then basename "$d"; fi
    done
  } | sort -u
}

# Отличается ли хоть один файл источника от установленной копии.
# Лишние файлы в установленной копии (например .env) изменением не считаются.
skill_differs() {
  local src="$1" installed="$2" f
  while IFS= read -r f; do
    cmp -s "$f" "$installed/${f#"$src"/}" || return 0
  done < <(find "$src" -type f)
  return 1
}

plan_skills() {
  local rt="$1" root stage name src status tag staged=0
  root="$(runtime_home "$rt")/skills"
  stage="$BUILD_DIR/stage/$rt"
  mkdir -p "$stage/skills"
  while IFS= read -r name; do
    tag=""
    if [ -f "$OVERLAY_SKILLS_DIR/$name/SKILL.md" ]; then
      src="$OVERLAY_SKILLS_DIR/$name"; tag=" (overlay)"
    else
      src="$UPSTREAM_DIR/skills/$name"
    fi
    if [ ! -d "$root/$name" ]; then
      status=new
    elif skill_differs "$src" "$root/$name"; then
      status=changed
    else
      status=same
    fi
    if [ "$status" != same ]; then
      cp -R "$src" "$stage/skills/$name"
      staged=$((staged + 1))
    fi
    info "SKILL   $rt/$name: $status$tag"
  done < <(skill_names)
  copy_lf "$UPSTREAM_DIR/install.sh" "$stage/install.sh"
  SKILL_STAGED[$rt]="$staged"
}

# Вернуть в новую копию скилла файлы .env из прежней.
restore_env_files() {
  local old="$1" new="$2" f rel
  while IFS= read -r f; do
    rel="${f#"$old"/}"
    if [ -e "$new/$rel" ]; then continue; fi
    mkdir -p "$(dirname "$new/$rel")"
    cp -p "$f" "$new/$rel"
    info "KEPT    $new/$rel"
  done < <(find "$old" -type f -name '.env')
}

apply_skills() {
  local rt="$1" stage before d name dest
  if [ "${SKILL_STAGED[$rt]:-0}" -eq 0 ]; then
    info "SKILL   $rt: без изменений"
    return 0
  fi
  stage="$BUILD_DIR/stage/$rt"
  before="$(list_skill_backups "$rt")"
  "$BASH" "$stage/install.sh" all "--$rt"
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if grep -Fxq -- "$d" <<< "$before"; then continue; fi
    name="$(basename "$d")"
    name="${name%.backup-*}"
    restore_env_files "$d" "$(runtime_home "$rt")/skills/$name"
    dest="$(backup_dir)/skills/$rt"
    mkdir -p "$dest"
    mv "$d" "$dest/"
    info "SWEPT   $d -> $dest/"
  done < <(list_skill_backups "$rt")
}
```

Переносятся только backup-папки, которых не было до запуска `install.sh`. Папки от прежних ручных запусков пользователя харнес не трогает.

- [ ] **Step 5: Подключить шаги в `harness.sh`**

В `overlay/harness.sh` заменить функцию `main` целиком на:

```bash
main() {
  local mode="${1:-plan}" rt
  case "$mode" in
    plan|apply) ;;
    *) usage; exit 2 ;;
  esac
  check_prereqs
  load_profile
  validate_profile
  detect_runtimes
  reset_build_dir
  info "режим: $mode"

  for rt in "${ACTIVE_RUNTIMES[@]}"; do
    plan_skills "$rt"
    plan_rules "$rt"
  done

  show_pending
  if [ "$mode" = apply ]; then
    commit_pending
    for rt in "${ACTIVE_RUNTIMES[@]}"; do
      apply_skills "$rt"
    done
  else
    info "это был plan: ничего не записано. Применить: overlay/harness.sh apply"
  fi
  print_notes
}
```

- [ ] **Step 6: Запустить все тесты**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 45, failed: 0`. Тест `test_rules_idempotent` теперь проверяет идемпотентность вместе со скиллами.

- [ ] **Step 7: Commit**

```bash
git add overlay/lib/stage.sh overlay/lib/backup.sh overlay/harness.sh overlay/tests/cases/skills.sh
git commit -m "Добавлена установка скиллов через стейджинг вокруг install.sh апстрима" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Хуки и слияние settings.json

**Files:**
- Create: `overlay/lib/settings.sh`, `overlay/lib/settings.jq`
- Modify: `overlay/harness.sh` (функция `main`)
- Test: `overlay/tests/cases/hooks.sh`

**Interfaces:**
- Consumes: `jqx`, `native_path`, `copy_lf`, `runtime_home`, `warn`, `info`, `die` (Task 1); `propose_file` (Task 4); переменные `WIKI_DIR`, `AUTO_MEMORY_OFF`, `HOOK_COMMAND_STYLE`, `HOOK_BASH`, `RENDER_DIR`, `UPSTREAM_DIR`, `OVERLAY_DIR`.
- Produces: `hook_command <script-name>` (stdout: строка `command` для `settings.json`), `plan_hooks` (предлагает два файла хуков с режимом 755 и, если есть семантическая разница, `settings.json`).

Вызывается только когда активен рантайм `claude` и `WIKI_ENABLED=1`.

Форма команды хука:
- `direct` — строка апстрима как есть: `$HOME/.claude/hooks/wiki-anchor.sh`;
- `explicit` — `"<HOOK_BASH>" "<абсолютный путь>"`, путь в Windows-форме через `native_path`. Нужна, если Claude Code на нативном Windows не исполняет `.sh` напрямую (выясняется в Task 9).

Существующая запись ищется по имени скрипта (`wiki-anchor.sh`), а не по полной строке команды. Поэтому смена формы обновляет запись, а не плодит вторую.

- [ ] **Step 1: Написать падающие тесты**

`overlay/tests/cases/hooks.sh`:

```bash
_SETTINGS() { printf '%s' "$HOME/.claude/settings.json"; }

test_hooks_installed() {
  run_ok apply
  assert_file "$HOME/.claude/hooks/wiki-anchor.sh"
  assert_file "$HOME/.claude/hooks/wiki-reminder.sh"
  [ -x "$HOME/.claude/hooks/wiki-anchor.sh" ] || fail "хук не исполняемый"
  if has_cr "$HOME/.claude/hooks/wiki-anchor.sh"; then fail "в хуке остались CR"; fi
  assert_eq "$(jqt -r '.env.WIKI_VAULT' < "$(_SETTINGS)")" "$SB/wiki"
  assert_eq "$(jqt -r '.hooks.SessionStart[0].matcher' < "$(_SETTINGS)")" 'startup|resume|compact'
  assert_eq "$(jqt -r '.hooks.SessionStart[0].hooks[0].command' < "$(_SETTINGS)")" '$HOME/.claude/hooks/wiki-anchor.sh'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit[0].hooks[0].command' < "$(_SETTINGS)")" '$HOME/.claude/hooks/wiki-reminder.sh'
  assert_eq "$(jqt -r 'has("autoMemoryEnabled")' < "$(_SETTINGS)")" 'false'
}

test_hooks_foreign_preserved_no_dupes() {
  cat > "$(_SETTINGS)" <<'JSON'
{
  "model": "opus",
  "env": { "FOO": "1" },
  "hooks": {
    "SessionStart": [ { "matcher": "startup", "hooks": [ { "type": "command", "command": "echo mine" } ] } ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "echo stop" } ] } ]
  }
}
JSON
  run_ok apply
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(jqt -r '.model' < "$(_SETTINGS)")" 'opus'
  assert_eq "$(jqt -r '.env.FOO' < "$(_SETTINGS)")" '1'
  assert_eq "$(jqt -r '.hooks.SessionStart | length' < "$(_SETTINGS)")" '2'
  assert_eq "$(jqt -r '.hooks.SessionStart[0].hooks[0].command' < "$(_SETTINGS)")" 'echo mine'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit | length' < "$(_SETTINGS)")" '1'
  assert_eq "$(jqt -r '.hooks.Stop[0].hooks[0].command' < "$(_SETTINGS)")" 'echo stop'
  assert_file "$HOME/.kisa-harness/backups/20260101-000000/.claude/settings.json"
  assert_no_path "$HOME/.kisa-harness/backups/20260101-000001"
}

test_hooks_wiki_off() {
  write_profile 'WIKI_ENABLED=0'
  run_ok apply
  assert_no_path "$HOME/.claude/hooks"
  assert_no_path "$(_SETTINGS)"
}

test_hooks_no_claude_runtime() {
  rm -rf "$HOME/.claude"
  run_ok apply
  assert_no_path "$HOME/.claude"
  assert_file "$CODEX_HOME/AGENTS.md"
}

test_hooks_invalid_json_stops_before_any_write() {
  printf '{broken' > "$(_SETTINGS)"
  local before; before="$(tree_hash "$HOME")"
  run_fail E_JSON apply
  assert_eq "$(tree_hash "$HOME")" "$before"
}

test_hooks_explicit_style() {
  write_profile 'HOOK_COMMAND_STYLE=explicit' 'HOOK_BASH="C:/Program Files/Git/bin/bash.exe"'
  run_ok apply
  local cmd; cmd="$(jqt -r '.hooks.SessionStart[0].hooks[0].command' < "$(_SETTINGS)")"
  case "$cmd" in
    '"C:/Program Files/Git/bin/bash.exe" "'*'/.claude/hooks/wiki-anchor.sh"') ;;
    *) fail "неожиданная команда: $cmd" ;;
  esac
}

test_hooks_style_switch_updates_in_place() {
  run_ok apply
  write_profile 'HOOK_COMMAND_STYLE=explicit' 'HOOK_BASH="C:/Program Files/Git/bin/bash.exe"'
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(jqt -r '.hooks.SessionStart | length' < "$(_SETTINGS)")" '1'
  assert_eq "$(jqt -r '.hooks.UserPromptSubmit | length' < "$(_SETTINGS)")" '1'
  assert_contains "$(_SETTINGS)" 'bash.exe'
}

test_hooks_automem_off() {
  write_profile 'AUTO_MEMORY_OFF=1'
  run_ok apply
  assert_eq "$(jqt -r '.autoMemoryEnabled' < "$(_SETTINGS)")" 'false'
  assert_contains "$HOME/.claude/CLAUDE.md" '## Память'
}

test_hooks_same_semantics_not_rewritten() {
  run_ok apply
  jqt -c . < "$(_SETTINGS)" > "$SB/compact.json"
  cp "$SB/compact.json" "$(_SETTINGS)"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  cmp -s "$(_SETTINGS)" "$SB/compact.json" || fail "файл с той же семантикой был переписан"
}

test_hooks_missing_wiki_pages_warn() {
  run_ok plan
  assert_contains "$SB/out.log" 'WARN'
  assert_contains "$SB/out.log" 'claude-code/pages/overview.md'
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh hooks`
Expected: `test_hooks_wiki_off` и `test_hooks_no_claude_runtime` — ok (хуки еще не ставятся вообще), остальные 8 — FAIL.

- [ ] **Step 3: Написать `settings.jq`**

`overlay/lib/settings.jq`:

```jq
# Слияние хуков харнеса в settings.json Claude Code.
# Вход: текущий settings.json (или {}).
# Аргументы: $ex (slurpfile settings.hooks.example.json апстрима), $wiki,
#            $anchor, $reminder (строки command), $automem_off ("0"|"1").

# Если на событии уже есть хук с этим скриптом - обновить его command,
# иначе добавить запись апстрима. Чужие записи не трогаются.
def upsert($entry; $script):
  if any(.[]?; any(.hooks[]?; (.command // "") | contains($script)))
  then map(if has("hooks")
           then .hooks |= map(if ((.command // "") | contains($script))
                              then .command = $entry.hooks[0].command
                              else . end)
           else . end)
  else . + [$entry] end;

def with_cmd($cmd): .hooks |= map(.command = $cmd);

($ex[0].hooks.SessionStart[0]       | with_cmd($anchor))   as $a
| ($ex[0].hooks.UserPromptSubmit[0] | with_cmd($reminder)) as $r
| .env = ((.env // {}) + {WIKI_VAULT: $wiki})
| .hooks = (.hooks // {})
| .hooks.SessionStart     = ((.hooks.SessionStart // [])     | upsert($a; "wiki-anchor.sh"))
| .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | upsert($r; "wiki-reminder.sh"))
| if $automem_off == "1" then .autoMemoryEnabled = false else . end
```

- [ ] **Step 4: Написать `settings.sh`**

`overlay/lib/settings.sh`:

```bash
# Хуки-якоря вики для Claude Code и слияние settings.json.
# Скрипты хуков копируются из апстрима без правок (кроме \r): путь к вики
# уходит в env.WIKI_VAULT, который wiki-anchor.sh уже читает.

HOOK_SCRIPTS="wiki-anchor.sh wiki-reminder.sh"

hook_command() {
  local name="$1"
  if [ "$HOOK_COMMAND_STYLE" = explicit ]; then
    printf '"%s" "%s"' "$HOOK_BASH" "$(native_path "$(runtime_home claude)/hooks/$name")"
  else
    printf '%s' "\$HOME/.claude/hooks/$name"
  fi
}

plan_hooks() {
  local claude_home name src settings cur merged example
  claude_home="$(runtime_home claude)"

  for name in overview.md components.md; do
    [ -f "$WIKI_DIR/claude-code/pages/$name" ] ||
      warn "в вики нет claude-code/pages/$name - хук сошлется на несуществующую страницу"
  done

  for name in $HOOK_SCRIPTS; do
    src="$RENDER_DIR/claude/hooks/$name"
    copy_lf "$UPSTREAM_DIR/global-config/hooks/$name" "$src"
    propose_file "$src" "$claude_home/hooks/$name" 755
  done

  settings="$claude_home/settings.json"
  cur="$RENDER_DIR/claude/settings.current.json"
  merged="$RENDER_DIR/claude/settings.json"
  if [ -s "$settings" ]; then
    jq empty "$settings" >/dev/null 2>&1 ||
      die "E_JSON невалидный JSON: $settings. Исправьте файл вручную, харнес его не трогает."
    copy_lf "$settings" "$cur"
  else
    mkdir -p "$(dirname "$cur")"
    printf '{}\n' > "$cur"
  fi

  example="$(native_path "$UPSTREAM_DIR/global-config/settings.hooks.example.json")"
  jqx --slurpfile ex "$example" \
      --arg wiki "$WIKI_DIR" \
      --arg anchor "$(hook_command wiki-anchor.sh)" \
      --arg reminder "$(hook_command wiki-reminder.sh)" \
      --arg automem_off "$AUTO_MEMORY_OFF" \
      -f "$(native_path "$OVERLAY_DIR/lib/settings.jq")" < "$cur" > "$merged"

  # jq переформатирует файл. Если по смыслу ничего не изменилось - не трогаем,
  # иначе первый же запуск переписал бы settings.json ради пробелов.
  if [ -s "$settings" ] && [ "$(jqx -S . < "$cur")" = "$(jqx -S . < "$merged")" ]; then
    info "SAME    $settings"
  else
    propose_file "$merged" "$settings"
  fi
}
```

`jq empty "$settings"` вызывается без `jqx` намеренно: здесь нужен автоматический перевод MSYS-пути `/tmp/...` в Windows-путь, а значений-аргументов нет.

- [ ] **Step 5: Подключить шаг в `harness.sh`**

В `overlay/harness.sh` в функции `main` сразу после цикла `for rt in ...; do plan_skills; plan_rules; done` добавить:

```bash
  if has_runtime claude && [ "$WIKI_ENABLED" = 1 ]; then
    plan_hooks
  fi
```

- [ ] **Step 6: Запустить все тесты**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 55, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add overlay/lib/settings.sh overlay/lib/settings.jq overlay/harness.sh overlay/tests/cases/hooks.sh
git commit -m "Добавлены хуки-якоря вики и слияние settings.json через jq" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Подключение MCP deploychan

**Files:**
- Create: `overlay/lib/mcp.sh`
- Modify: `overlay/harness.sh` (функция `main`)
- Test: `overlay/tests/cases/mcp.sh`

**Interfaces:**
- Consumes: `upsert_block`, `outside_block` (Task 2); `propose_file` (Task 4); `runtime_home`, `info`, `warn`, `note` (Task 1); массив `ACTIVE_RUNTIMES`; переменная `RENDER_DIR`.
- Produces: `plan_mcp` (для каждого активного рантайма), `apply_mcp` (выполняет `claude mcp add`, если запланировано). Переменная `CLAUDE_BIN` (по умолчанию `claude`, переопределяется `HARNESS_CLAUDE_BIN`).

Проверенные факты (официальная документация, 2026-09-20):
- Claude Code: `claude mcp add --transport http --scope user <name> <url>`; опции идут перед именем. Есть `claude mcp list`. Код возврата `claude mcp get` для отсутствующего сервера не задокументирован, поэтому наличие определяется по выводу `claude mcp list`.
- Codex: для HTTP-сервера под `[mcp_servers.<name>]` обязателен только ключ `url`; ключей `transport` и `type` не существует, тип выводится из наличия `url`. В статье `mcp-connection` из MCP deploychan указан `transport = "http"` — **в блок его не писать**.
- Hermes: путь к MCP-конфигу в материалах MCP не назван. Не угадываем, печатаем инструкцию.

- [ ] **Step 1: Написать падающие тесты**

`overlay/tests/cases/mcp.sh`:

```bash
_TOML() { printf '%s' "$CODEX_HOME/config.toml"; }

_stub_claude() {
  cat > "$SB/claude" <<'STUB'
#!/usr/bin/env bash
here="$(dirname "$0")"
printf '%s\n' "$*" >> "$here/claude.log"
if [ "${1:-} ${2:-}" = "mcp list" ] && [ -f "$here/connected" ]; then
  echo "deploychan: https://mcp.deploychan.webcam/mcp (HTTP) - Connected"
fi
exit 0
STUB
  chmod +x "$SB/claude"
  : > "$SB/claude.log"
  export HARNESS_CLAUDE_BIN="$SB/claude"
}

test_mcp_codex_block_created() {
  run_ok apply
  assert_contains "$(_TOML)" '# >>> kisa-harness >>>'
  assert_contains "$(_TOML)" '[mcp_servers.deploychan]'
  assert_contains "$(_TOML)" 'url = "https://mcp.deploychan.webcam/mcp"'
  assert_contains "$(_TOML)" '# <<< kisa-harness <<<'
  assert_not_contains "$(_TOML)" 'transport'
}

test_mcp_codex_existing_config_preserved() {
  printf 'model = "gpt-5"\n\n[tools]\nweb_search = true\n' > "$(_TOML)"
  cp "$(_TOML)" "$SB/orig.toml"
  run_ok apply
  head -c "$(wc -c < "$SB/orig.toml")" "$(_TOML)" | cmp -s - "$SB/orig.toml" || fail "чужой config.toml изменен"
  assert_contains "$(_TOML)" '[mcp_servers.deploychan]'
  local before; before="$(cksum < "$(_TOML)")"
  export HARNESS_TS="20260101-000001"
  run_ok apply
  assert_eq "$(cksum < "$(_TOML)")" "$before"
}

test_mcp_codex_foreign_section_untouched() {
  printf '[mcp_servers.deploychan]\nurl = "https://example.com/own"\n' > "$(_TOML)"
  local before; before="$(cksum < "$(_TOML)")"
  run_ok apply
  assert_eq "$(cksum < "$(_TOML)")" "$before"
  assert_contains "$SB/out.log" 'MCP     codex: deploychan уже описан'
}

test_mcp_claude_no_cli_gives_instruction() {
  run_ok apply
  assert_contains "$SB/out.log" 'claude mcp add --transport http --scope user deploychan https://mcp.deploychan.webcam/mcp'
}

test_mcp_claude_plan_does_not_add() {
  _stub_claude
  run_ok plan
  assert_contains "$SB/claude.log" 'mcp list'
  assert_not_contains "$SB/claude.log" 'mcp add'
}

test_mcp_claude_apply_adds() {
  _stub_claude
  run_ok apply
  assert_contains "$SB/claude.log" 'mcp add --transport http --scope user deploychan https://mcp.deploychan.webcam/mcp'
}

test_mcp_claude_already_connected() {
  _stub_claude
  : > "$SB/connected"
  run_ok apply
  assert_not_contains "$SB/claude.log" 'mcp add'
  assert_contains "$SB/out.log" 'MCP     claude: deploychan уже подключен'
}

test_mcp_hermes_instruction() {
  run_ok plan
  assert_contains "$SB/out.log" 'Hermes'
  assert_contains "$SB/out.log" '"url":"https://mcp.deploychan.webcam/mcp"'
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh mcp`
Expected: 8 FAIL.

- [ ] **Step 3: Написать `mcp.sh`**

`overlay/lib/mcp.sh`:

```bash
# Подключение MCP deploychan. Правило: путь или формат не подтвержден -
# печатаем инструкцию человеку, а не пишем наугад.

MCP_NAME="deploychan"
MCP_URL="https://mcp.deploychan.webcam/mcp"
CLAUDE_BIN="${HARNESS_CLAUDE_BIN:-claude}"
MCP_CLAUDE_TODO=0
TOML_BEGIN='# >>> kisa-harness >>>'
TOML_END='# <<< kisa-harness <<<'

plan_mcp() {
  local rt
  for rt in "${ACTIVE_RUNTIMES[@]}"; do
    case "$rt" in
      claude) plan_mcp_claude ;;
      codex)  plan_mcp_codex ;;
      hermes) note "Hermes: путь к MCP-конфигу не подтвержден, добавьте сервер вручную: {\"mcpServers\":{\"$MCP_NAME\":{\"type\":\"http\",\"url\":\"$MCP_URL\"}}}" ;;
    esac
  done
}

plan_mcp_claude() {
  local cmd="claude mcp add --transport http --scope user $MCP_NAME $MCP_URL" listed
  if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
    note "Claude Code: CLI не найден в PATH. Подключите MCP вручную: $cmd (если $MCP_NAME уже подключен как коннектор claude.ai - пропустите)"
    return 0
  fi
  listed="$("$CLAUDE_BIN" mcp list 2>/dev/null || true)"
  if grep -qw -- "$MCP_NAME" <<< "$listed"; then
    info "MCP     claude: $MCP_NAME уже подключен"
  else
    info "MCP     claude: будет выполнено: $cmd"
    MCP_CLAUDE_TODO=1
  fi
}

plan_mcp_codex() {
  local cfg content out outside
  cfg="$(runtime_home codex)/config.toml"
  if [ -f "$cfg" ]; then
    outside="$(outside_block "$cfg" "$TOML_BEGIN" "$TOML_END")"
    if grep -q '^[[:space:]]*\[mcp_servers\.deploychan\]' <<< "$outside"; then
      info "MCP     codex: $MCP_NAME уже описан в $cfg вне блока харнеса, не трогаю"
      return 0
    fi
  fi
  content="$RENDER_DIR/codex/mcp.block.toml"
  out="$RENDER_DIR/codex/config.toml"
  mkdir -p "$(dirname "$content")"
  printf '[mcp_servers.%s]\nurl = "%s"\n' "$MCP_NAME" "$MCP_URL" > "$content"
  upsert_block "$cfg" "$content" "$out" "$TOML_BEGIN" "$TOML_END"
  propose_file "$out" "$cfg"
}

apply_mcp() {
  [ "$MCP_CLAUDE_TODO" = 1 ] || return 0
  if "$CLAUDE_BIN" mcp add --transport http --scope user "$MCP_NAME" "$MCP_URL"; then
    info "MCP     claude: $MCP_NAME подключен"
  else
    warn "claude mcp add завершился с ошибкой"
    note "Claude Code: подключите MCP вручную: claude mcp add --transport http --scope user $MCP_NAME $MCP_URL"
  fi
}
```

Сбой `claude mcp add` не роняет установку: к этому моменту файлы уже записаны, и откатывать их из-за недоступного CLI незачем. Команда уходит в список «Сделать вручную».

- [ ] **Step 4: Подключить шаги в `harness.sh`**

В `overlay/harness.sh` заменить функцию `main` целиком на итоговую версию:

```bash
main() {
  local mode="${1:-plan}" rt
  case "$mode" in
    plan|apply) ;;
    *) usage; exit 2 ;;
  esac
  check_prereqs
  load_profile
  validate_profile
  detect_runtimes
  reset_build_dir
  info "режим: $mode"

  for rt in "${ACTIVE_RUNTIMES[@]}"; do
    plan_skills "$rt"
    plan_rules "$rt"
  done
  if has_runtime claude && [ "$WIKI_ENABLED" = 1 ]; then
    plan_hooks
  fi
  plan_mcp

  show_pending
  if [ "$mode" = apply ]; then
    commit_pending
    for rt in "${ACTIVE_RUNTIMES[@]}"; do
      apply_skills "$rt"
    done
    apply_mcp
  else
    info "это был plan: ничего не записано. Применить: overlay/harness.sh apply"
  fi
  print_notes
}
```

- [ ] **Step 5: Запустить все тесты**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 63, failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add overlay/lib/mcp.sh overlay/harness.sh overlay/tests/cases/mcp.sh
git commit -m "Добавлено подключение MCP deploychan для Claude Code и Codex" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Лаунчер для Windows, README, гигиена репозитория

**Files:**
- Create: `overlay/harness.ps1`, `overlay/README.md`
- Test: `overlay/tests/cases/repo.sh`

**Interfaces:**
- Consumes: `overlay/harness.sh` целиком.
- Produces: `overlay/harness.ps1 [plan|apply]` — находит Git Bash и передает управление `harness.sh`; код возврата пробрасывается.

- [ ] **Step 1: Написать падающие тесты гигиены**

`overlay/tests/cases/repo.sh`:

```bash
# Конвенция апстрима: без букв U+0451 и U+0401. Байты заданы escape-последовательностями,
# чтобы сам тест не содержал запрещенных букв.
test_repo_no_yo_letters() {
  local hits
  hits="$(grep -rlI -e $'\xd1\x91' -e $'\xd0\x81' "$OVERLAY_DIR" --exclude-dir=.build || true)"
  [ -z "$hits" ] || fail "буква U+0451/U+0401 в файлах:"$'\n'"$hits"
}

test_repo_lf_only() {
  local f hits=""
  while IFS= read -r f; do
    if has_cr "$f"; then hits="$hits"$'\n'"$f"; fi
  done < <(find "$OVERLAY_DIR" -type f -not -path '*/.build/*' -not -name 'profile.env')
  [ -z "$hits" ] || fail "CRLF в файлах:$hits"
}

test_repo_launcher_and_readme_exist() {
  assert_file "$OVERLAY_DIR/harness.ps1"
  assert_file "$OVERLAY_DIR/README.md"
  assert_contains "$OVERLAY_DIR/harness.ps1" 'Git\bin\bash.exe'
  assert_contains "$OVERLAY_DIR/README.md" 'harness.sh plan'
}

test_repo_upstream_files_untouched() {
  # База сравнения - точка расхождения с апстримом; пока remote upstream не
  # добавлен - коммит форка 63c6f6b. После git pull upstream база сдвигается
  # сама, и чужие обновления не считаются нашими правками.
  local base changed
  base="$(git -C "$REPO_DIR" merge-base HEAD upstream/main 2>/dev/null || echo 63c6f6b)"
  changed="$(git -C "$REPO_DIR" diff --name-only "$base" | grep -v '^overlay/' || true)"
  [ -z "$changed" ] || fail "изменены файлы апстрима:"$'\n'"$changed"
}
```

- [ ] **Step 2: Запустить и убедиться, что падает нужный тест**

Run: `bash overlay/tests/run.sh repo`
Expected: `test_repo_launcher_and_readme_exist` — FAIL (нет `harness.ps1`). Остальные три должны проходить; если `test_repo_no_yo_letters` или `test_repo_lf_only` падают — исправить названные файлы до продолжения.

- [ ] **Step 3: Написать `harness.ps1`**

`overlay/harness.ps1` (только ASCII: Windows PowerShell 5.1 читает файл без BOM как ANSI, кириллица превратится в мусор):

```powershell
# Launcher for Windows: finds Git Bash and runs harness.sh.
# "bash" from PATH is not used on purpose: on Windows the first match is
# C:\Windows\System32\bash.exe, a WSL stub.
$ErrorActionPreference = 'Stop'

$candidates = @(
  (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
  (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
)
$bash = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
  Write-Host '[harness] E_PREREQ Git Bash not found. Install Git for Windows: winget install Git.Git'
  exit 1
}

# Forward slashes: dirname inside bash does not understand backslashes.
$script = (Join-Path $PSScriptRoot 'harness.sh') -replace '\\', '/'
& $bash $script @args
exit $LASTEXITCODE
```

- [ ] **Step 4: Написать `README.md`**

`overlay/README.md`:

````markdown
# overlay — личный харнес поверх KISA Stack

Все, что здесь лежит, — мое. Все, что вне `overlay/`, — апстрим Кисы, и я его
не правлю: так `git pull upstream` никогда не дает конфликтов.

## Быстрый старт

```bash
cp overlay/profile.example.env overlay/profile.env   # и заполнить WIKI_DIR
overlay/harness.sh plan                              # показать, что изменится
overlay/harness.sh apply                             # бэкап и запись
```

На Windows из PowerShell:

```
.\overlay\harness.ps1 plan
```

Нужны `jq` и bash >= 4.4 (на Windows — Git for Windows). Харнес сам ничего не
доустанавливает: не найдет — скажет, какой командой поставить.

## Что ставится

| | Claude Code | Codex | Hermes |
|---|---|---|---|
| Скиллы | да | да | да |
| Правила | блок в `~/.claude/CLAUDE.md` | блок в `~/.codex/AGENTS.md` | нет |
| Хуки-якоря вики | да, при `WIKI_ENABLED=1` | нет | нет |
| MCP deploychan | `claude mcp add` или инструкция | блок в `config.toml` | инструкция |

Рантайм без домашнего каталога пропускается.

## Как это устроено

- **Скиллы** ставит `install.sh` апстрима, без правок. Харнес собирает в
  `.build/stage/` только новые и изменившиеся скиллы и запускает его оттуда.
  Скилл из `overlay/skills/` замещает одноименный апстримный.
- **Правила** — шаблон апстрима с подставленными путями и вырезанными
  выключенными секциями, плюс мой `overlay/rules/*.md` в конце. Вставляются
  между `<!-- kisa-harness:begin -->` и `<!-- kisa-harness:end -->`. Все вне
  маркеров не меняется.
- **`settings.json`** сливается через `jq`: добавляются `env.WIKI_VAULT` и два
  хука, чужие ключи и хуки сохраняются.
- **`plan`** пишет только в `overlay/.build/`. **`apply`** перед записью кладет
  прежнюю версию каждого измененного файла в
  `~/.kisa-harness/backups/<timestamp>/`.

## Профиль

Ключи и значения по умолчанию описаны в `profile.example.env`. `profile.env` в
git не попадает: он зависит от машины.

Личные добавки к правилам — в `overlay/rules/claude.md` и
`overlay/rules/agents.md`. Пустой файл ничего не добавляет. HTML-комментарии
туда не писать: содержимое дописывается в правила как есть.

## Обновление из апстрима

```bash
git remote add upstream https://github.com/howdeploy/kisa-stack.git   # один раз
git pull upstream main
bash overlay/tests/run.sh
overlay/harness.sh plan
```

Тесты рендеринга работают на настоящих шаблонах Кисы. Если она переименует
заголовок, по которому вырезается секция, упадет тест с `E_ANCHOR` — поправьте
якорь в `overlay/lib/render.sh`.

## Откат

Бэкапы — обычные файлы с зеркалом путей от домашнего каталога:

```bash
cp ~/.kisa-harness/backups/<timestamp>/.claude/CLAUDE.md ~/.claude/CLAUDE.md
```

Прежние версии скиллов лежат в `~/.kisa-harness/backups/<timestamp>/skills/<runtime>/`.

## Известные ограничения

- Хуки для Codex и Hermes и правила для Hermes не ставятся: апстрим их не дает.
- Слияние `config.toml` текстовое. Не дописывайте свои ключи сразу после
  маркера `# <<< kisa-harness <<<` без заголовка таблицы: TOML отнесет их к
  таблице `mcp_servers.deploychan`.
- При обновлении скилла из прежней копии возвращаются только файлы `.env`.
  Остальные локальные правки уходят в бэкап.
- Скрипты внутри скиллов апстрима копируются как есть. Если Git на Windows
  выдал их с CRLF, выполните `git config core.autocrlf input` и перечекаутьте.

## Тесты

```bash
bash overlay/tests/run.sh           # все
bash overlay/tests/run.sh render    # по части имени
```

Каждый тест получает свой временный `HOME`, настоящие `~/.claude`, `~/.codex`
и `~/.hermes` не затрагиваются.
````

- [ ] **Step 5: Запустить все тесты**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 67, failed: 0`.

- [ ] **Step 6: Проверить лаунчер вручную (только Windows)**

Run в PowerShell из корня репо: `powershell -NoProfile -ExecutionPolicy Bypass -File overlay\harness.ps1 frobnicate`
Expected: строка `Usage: .../overlay/harness.sh [plan|apply]` и код возврата 2 (`$LASTEXITCODE`). Это подтверждает, что Git Bash найден, путь передан корректно и код возврата проброшен. Настоящий `plan` здесь не запускать — он относится к Task 9.

- [ ] **Step 7: Commit**

```bash
git add overlay/harness.ps1 overlay/README.md overlay/tests/cases/repo.sh
git commit -m "Добавлены лаунчер для Windows, README слоя и тесты гигиены" \
           -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Раскатка на машине владельца

Задача не для субагента: она меняет настоящие `~/.claude` и `~/.codex`, требует перезапуска сессии Claude Code и явных «ок» владельца. Выполняет основной агент вместе с владельцем. Каждый шаг с записью вне репо — только после подтверждения.

**Files:**
- Create: `overlay/profile.env` (вне git)
- Временные, удаляются в конце: `~/.kisa-harness/spike/spike.sh`, запись в `.claude/settings.local.json` репо

- [ ] **Step 1: Проверить пререквизиты в свежей сессии**

Run: `command -v jq && jq --version && bash overlay/tests/run.sh`
Expected: путь к `jq`, версия, `passed: 67, failed: 0`. Если `jq` не виден — владелец перезапускает приложение Claude полностью.

- [ ] **Step 2: Добавить апстрим**

`gh` подтверждает, что форк `antonovkrez/kisa-stack` сделан от `howdeploy/kisa-stack`.

```bash
git remote add upstream https://github.com/howdeploy/kisa-stack.git
git remote -v
```

Expected: `origin` и `upstream`.

- [ ] **Step 3: Спайк — как Claude Code на Windows исполняет хук-команду**

От результата зависит только `HOOK_COMMAND_STYLE` в профиле. Обе формы уже реализованы и покрыты тестами.

Создать пробный скрипт:

```bash
mkdir -p "$HOME/.kisa-harness/spike"
cat > "$HOME/.kisa-harness/spike/spike.sh" <<'EOF'
#!/usr/bin/env bash
printf 'ran at %s via bash %s as %s\n' "$(date)" "$BASH_VERSION" "$0" >> "$HOME/.kisa-harness/spike/ran.log"
EOF
chmod +x "$HOME/.kisa-harness/spike/spike.sh"
```

С согласия владельца добавить в `.claude/settings.local.json` репо (файл уже в `.gitignore` апстрима; если в нем есть другие ключи — слить, не заменять):

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "$HOME/.kisa-harness/spike/spike.sh", "timeout": 10 } ] }
    ]
  }
}
```

Владелец открывает новую сессию Claude Code в этом репо. Затем:

Run: `cat "$HOME/.kisa-harness/spike/ran.log"`

- Файл есть и в нем строка `ran at ...` → форма `direct` работает. Записать в профиль `HOOK_COMMAND_STYLE=direct`.
- Файла нет → заменить `command` на `"C:/Program Files/Git/bin/bash.exe" "C:/Users/pideComputer/.kisa-harness/spike/spike.sh"`, владелец снова открывает новую сессию. Файл появился → `HOOK_COMMAND_STYLE=explicit`, `HOOK_BASH="C:/Program Files/Git/bin/bash.exe"`. Файла снова нет → СТОП: доложить владельцу, что хуки на этой машине не исполняются ни в одной форме, и выставить `WIKI_ENABLED=0` до выяснения.

Убрать за собой: удалить добавленную запись из `.claude/settings.local.json` и каталог спайка:

```bash
rm -rf "$HOME/.kisa-harness/spike"
```

- [ ] **Step 4: Заполнить профиль**

Путь к вики владелец сообщает после переименования папки (ожидается `C:/Users/pideComputer/Desktop/AIpreneurs/LLM Wiki`). Проверить, что папка существует, затем:

```bash
cp overlay/profile.example.env overlay/profile.env
```

Вписать `WIKI_DIR`, `HOOK_COMMAND_STYLE` и при необходимости `HOOK_BASH`. `RUNTIMES` оставить как есть: Hermes на машине нет, он будет пропущен.

Run: `git status --short`
Expected: `overlay/profile.env` в выводе нет (игнорируется).

- [ ] **Step 5: `plan` и ревью владельцем**

Run: `overlay/harness.sh plan`

Показать владельцу вывод целиком. Проверить вместе:
- `RUNTIME claude`, `RUNTIME codex`, `SKIP    runtime hermes`;
- дифф `~/.claude/CLAUDE.md`: существующий блок gstack не затронут, блок харнеса дописан в конец;
- дифф `~/.claude/settings.json`: существующие ключи и хуки на месте;
- дифф `~/.codex/AGENTS.md` и `~/.codex/config.toml`;
- список «Сделать вручную» (подключение MCP для Claude Code, если CLI не в PATH).

- [ ] **Step 6: `apply` — только после явного «ок» владельца**

Run: `overlay/harness.sh apply`
Expected: строки `BACKUP`, `WROTE`, `Installed ...` от `install.sh`, без ошибок.

Run: `overlay/harness.sh plan`
Expected: все строки `SAME` и `SKILL ...: same`, ни одного `NEW`/`CHANGED`.

- [ ] **Step 7: Проверить в живой сессии**

Владелец открывает новую сессию Claude Code. Ожидается: в контексте сессии есть блок «LLM Wiki — обязательная стартовая точка анализа» с путем к вики; список скиллов содержит `researcher`, `voice-summary` и остальные; скиллы gstack и superpowers на месте.

Если что-то не так — откат по `overlay/README.md`, раздел «Откат», и доклад владельцу. Самостоятельно не чинить.

- [ ] **Step 8: Проверить лаунчер PowerShell на настоящем профиле**

Run в PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File overlay\harness.ps1 plan`
Expected: тот же вывод, что в Step 6 после `apply` (все `SAME`), код возврата 0.

---

## Проверка покрытия спека

| Требование спека | Задача |
|---|---|
| Инвариант 1: все свое в `overlay/` | 1, тест `test_repo_upstream_files_untouched` (8) |
| Инвариант 2: `install.sh` буквально | 5 |
| Инвариант 3: слияние, не перезапись | 2, 4, 6, 7 |
| Инвариант 4: идемпотентность | `test_rules_idempotent`, `test_skills_second_run_is_noop`, `test_hooks_foreign_preserved_no_dupes`, `test_mcp_codex_existing_config_preserved` |
| Инвариант 5: `plan` не пишет | `test_rules_plan_writes_nothing`, `test_skills_plan_installs_nothing`, `test_mcp_claude_plan_does_not_add` |
| Инвариант 6: не угадывать | 7 (Hermes, отсутствие CLI) |
| Профиль и валидация | 1 |
| Пререквизиты, `jq` | 1 |
| Стейджинг, перенос backup-папок | 5 |
| Рендеринг, якоря, громкое падение | 3 |
| Управляемый блок, непарный маркер | 2, 4 |
| Хуки, `env.WIKI_VAULT`, дедупликация | 6 |
| deploychan по рантаймам | 7 |
| Ошибки до первой записи, бэкапы | 4, 6 (`*_stops_before_any_write`) |
| Тесты 1–12 спека | 1: `test_skills_clean_install` + `test_rules_created` + `test_hooks_installed`; 2: `test_rules_idempotent`; 3: `test_rules_foreign_content_preserved`; 4: `test_hooks_foreign_preserved_no_dupes`; 5: `test_hooks_wiki_off` + `test_rules_wiki_off`; 6: `test_render_missing_anchor_fails`; 7: `test_render_leftover_placeholder_fails`; 8: `test_skills_overlay_wins`; 9: `test_rules_plan_writes_nothing`; 10: `test_skills_update_sweeps_backup_and_keeps_env`; 11: `test_rules_unpaired_marker_stops_before_any_write`; 12: `test_skills_runtime_without_home_skipped` |
| Риск CRLF | 1 (`copy_lf`, `.gitattributes`), `test_render_crlf_template_same_result`, `test_block_crlf_markers`, `test_hooks_installed` |
| Спайк хуков на Windows | 9 |
| `harness.ps1` | 8 |
