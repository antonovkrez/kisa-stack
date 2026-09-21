# Переезд скиллов на харнес — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Команда `overlay/harness.sh capture apply` переносит личные скиллы из `~/.claude/skills` в `overlay/skills/`, откуда харнес разносит их по всем машинам.

**Architecture:** Новое действие рядом с существующей раскаткой: `harness.sh capture [plan|apply]`. Отбор — денилист из четырех правил, три из которых засеваются автоматически. Новый файл `overlay/lib/capture.sh` подхватывается существующим циклом `source` в `harness.sh`. Переезд пишет только внутрь репозитория; домашние каталоги рантаймов он читает, но не меняет ни в одном режиме.

**Tech Stack:** bash >= 4.4, awk, find, cp, basename, date. Тесты — существующий раннер `overlay/tests/run.sh`.

Спек: `overlay/docs/specs/2026-09-21-skill-capture-design.md`.

## Global Constraints

- Все новые файлы — только внутри `overlay/`. Ни один файл апстрима не меняется, включая корневые `.gitignore` и `README.md`, `install.sh`, `skills/`, `global-config/`.
- Переезд пишет только в `$OVERLAY_SKILLS_DIR`. Ни один режим не меняет `~/.claude`, `~/.codex`, `~/.hermes`, `~/.kisa-harness`.
- Режим `plan` не создает и не меняет ни одного файла.
- Файлы с именем `.env` не копируются никогда, на любом уровне вложенности. `overlay/skills/` коммитится в git, и ключ из `suno-music` не должен туда попасть.
- Зависимости: только bash >= 4.4, coreutils, `diff`, `sed`, `awk`, `find`, `cmp`, `jq`. Python и Node не используются. Команды `hostname` в пререквизитах нет — имя машины берется из `${HOSTNAME:-unknown}`.
- Каждое сообщение об ошибке начинается с ASCII-кода. Новых кодов план не вводит: единственная ошибка — `E_PROFILE`. Строки статуса начинаются с ASCII-токена: `CAPTURE`, `DENY`, `SKIP`, `WROTE`, `WARN`. Тесты опираются на эти токены; русский текст ищут только через `grep -F`.
- Конвенция репозитория: в коммитимых файлах нет буквы U+0451 и U+0401. Пишите через «е». Проверка: `grep -rlI -e $'\xd1\x91' -e $'\xd0\x81' overlay --exclude-dir=.build`.
- Все текстовые файлы — с окончаниями LF.
- Наличие `\r` нельзя проверять через `grep $'\r'`: в Git Bash такой шаблон совпадает с каждой строкой. В тестах — только помощник `has_cr` из `tests/run.sh`.
- В конвейерах под `set -o pipefail` нельзя писать `producer | grep -q`: сначала сохранить вывод в переменную, потом `grep -q ... <<< "$var"`.
- Шелл — Git Bash. Не PowerShell и не `C:\Windows\System32\bash.exe` (заглушка WSL). `jq` виден в PATH сам, обходной `export PATH` больше не нужен.
- Полный прогон тестов занимает несколько минут: задавайте командам щедрый таймаут (например 900000 мс).
- Настоящий `overlay/harness.sh` против своего реального `HOME` не запускать. Проверять только через `bash overlay/tests/run.sh`, где у каждого теста свой временный `HOME`.
- Сообщения коммитов — на русском, в стиле апстрима, с трейлером `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

## Карта файлов

| Файл | Ответственность | Задача |
|---|---|---|
| `overlay/lib/capture.sh` | отбор кандидатов и копирование | 2, 3 |
| `overlay/harness.sh` | грамматика команды, маршрутизация действия | 1 |
| `overlay/lib/detect.sh` | ключи профиля `CAPTURE_FROM`, `CAPTURE_DENY` | 1 |
| `overlay/profile.example.env` | документация ключей | 1 |
| `overlay/README.md` | раздел про переезд | 3 |
| `overlay/tests/cases/capture.sh` | тесты переезда | 1, 2, 3 |

Состояние на входе: полный прогон `bash overlay/tests/run.sh` дает `passed: 79, failed: 0`.

---

### Task 1: Грамматика команды и ключи профиля

**Files:**
- Modify: `overlay/harness.sh` (комментарий-заголовок, `usage`, `main`)
- Modify: `overlay/lib/detect.sh` (`load_profile`, `validate_profile`)
- Modify: `overlay/profile.example.env`
- Test: `overlay/tests/cases/capture.sh`

**Interfaces:**
- Consumes: `die`, `info` из `common.sh`; `check_prereqs`, `load_profile`, `validate_profile` из `detect.sh`; `assert_profile_kept_internals` из `harness.sh`.
- Produces:
  - Глобальные переменные профиля `CAPTURE_FROM` (`claude`|`codex`|`hermes`, дефолт `claude`) и `CAPTURE_DENY` (имена через пробел, дефолт пусто).
  - Грамматика `harness.sh capture [plan|apply]`, по умолчанию `plan`.
  - Функция `run_capture <plan|apply>` — в этой задаче заглушка, печатающая строку режима. Задача 2 заменяет ее целиком.

- [ ] **Step 1: Написать падающие тесты**

Создать `overlay/tests/cases/capture.sh`:

```bash
# Помощник: создать скилл в каталоге рантайма.
# _mk_skill <корень> <имя> <описание>
_mk_skill() {
  mkdir -p "$1/$2"
  printf -- '---\nname: %s\ndescription: %s\n---\nbody\n' "$2" "$3" > "$1/$2/SKILL.md"
}

test_capture_mode_accepted() {
  run_ok capture
  assert_contains "$SB/out.log" 'режим: capture plan'
}

test_capture_apply_submode_accepted() {
  run_ok capture apply
  assert_contains "$SB/out.log" 'режим: capture apply'
}

test_capture_unknown_submode_fails() {
  if run_harness capture frobnicate; then fail "неизвестный подрежим должен падать"; fi
}

test_capture_bad_from_fails() {
  write_profile 'CAPTURE_FROM=nosuch'
  run_fail E_PROFILE capture
}
```

- [ ] **Step 2: Запустить тесты и убедиться, что они падают**

Run: `bash overlay/tests/run.sh capture`
Expected: 4 теста, из них падают `test_capture_mode_accepted`, `test_capture_apply_submode_accepted` и `test_capture_bad_from_fails` (режим `capture` пока не распознается, `harness.sh` выходит с кодом 2). `test_capture_unknown_submode_fails` проходит вхолостую — неизвестный режим и сейчас падает. Итог: `passed: 1, failed: 3`.

- [ ] **Step 3: Добавить ключи профиля в `detect.sh`**

В `overlay/lib/detect.sh`, в функции `load_profile`, после строки `HOOK_BASH=""` и ДО строки `# shellcheck disable=SC1090` добавить:

```bash
  CAPTURE_FROM=claude
  CAPTURE_DENY=""
```

В функции `validate_profile`, после блока `case "$HOOK_COMMAND_STYLE" in ... esac` и перед `if [ "$HOOK_COMMAND_STYLE" = explicit ]`, добавить:

```bash
  case "$CAPTURE_FROM" in
    claude|codex|hermes) ;;
    *) die "E_PROFILE CAPTURE_FROM должен быть claude, codex или hermes, сейчас: $CAPTURE_FROM" ;;
  esac
```

- [ ] **Step 4: Задокументировать ключи в `profile.example.env`**

Дописать в конец `overlay/profile.example.env`:

```bash

# Из какого рантайма забирает скиллы overlay/harness.sh capture.
# Значения: claude, codex, hermes.
CAPTURE_FROM=claude

# Имена скиллов через пробел, которые не переезжают в overlay/skills.
# Апстримные и помеченные (gstack) отклоняются автоматически, сюда их писать не нужно.
CAPTURE_DENY=""
```

- [ ] **Step 5: Добавить грамматику в `harness.sh`**

В `overlay/harness.sh` заменить строку-комментарий 3 на две:

```bash
# Использование: overlay/harness.sh [plan|apply]            (по умолчанию plan)
#                overlay/harness.sh capture [plan|apply]    (по умолчанию plan)
```

Заменить `usage` целиком на:

```bash
usage() {
  printf 'Usage: %s [plan|apply]\n' "$0" >&2
  printf '       %s capture [plan|apply]\n' "$0" >&2
}
```

Заменить `main` целиком на:

```bash
main() {
  local action mode rt
  case "${1:-plan}" in
    plan|apply) action=install; mode="${1:-plan}" ;;
    capture)    action=capture; mode="${2:-plan}" ;;
    *) usage; exit 2 ;;
  esac
  case "$mode" in
    plan|apply) ;;
    *) usage; exit 2 ;;
  esac
  trap print_notes EXIT
  check_prereqs
  load_profile
  assert_profile_kept_internals
  validate_profile

  if [ "$action" = capture ]; then
    run_capture "$mode"
    return 0
  fi

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
}
```

Переезд не вызывает ни `detect_runtimes`, ни `reset_build_dir`: он ничего не рендерит, а требовать наличия хотя бы одного рантайма ему незачем — нужный каталог он проверяет сам.

- [ ] **Step 6: Написать заглушку `capture.sh`**

Создать `overlay/lib/capture.sh`:

```bash
# Переезд скиллов с этой машины в overlay/skills/.
# Разовая операция: после нее источник истины - репозиторий, а не машина.

run_capture() {
  local mode="$1"
  info "режим: capture $mode"
}
```

- [ ] **Step 7: Запустить тесты и убедиться, что они проходят**

Run: `bash overlay/tests/run.sh capture`
Expected: `passed: 4, failed: 0`.

- [ ] **Step 8: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 83, failed: 0` (79 прежних + 4 новых). Прежние тесты не должны сломаться: грамматика `plan`/`apply` сохранена.

- [ ] **Step 9: Commit**

```bash
git add overlay/harness.sh overlay/lib/detect.sh overlay/lib/capture.sh \
        overlay/profile.example.env overlay/tests/cases/capture.sh
git commit -m "Добавлена грамматика overlay/harness.sh capture и ключи профиля переезда" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Отбор кандидатов

**Files:**
- Modify: `overlay/lib/capture.sh`
- Test: `overlay/tests/cases/capture.sh`

**Interfaces:**
- Consumes: `info`, `warn`, `runtime_home` из `common.sh`; переменные `UPSTREAM_DIR`, `OVERLAY_SKILLS_DIR`, `CAPTURE_FROM`, `CAPTURE_DENY`; помощник `_mk_skill` из тестов задачи 1.
- Produces:
  - `skill_description <путь-к-SKILL.md>` — значение `description:` из фронтматтера, в stdout. Пусто, если фронтматтера нет.
  - `capture_decision <имя> <путь-к-SKILL.md>` — в stdout `capture` либо `deny:<причина>`.
  - `run_capture <plan|apply>` — печатает решение по каждому скиллу. В этой задаче запись еще не делается.

Правила отклонения, по первому сработавшему:

| Правило | Признак | Причина в выводе |
|---|---|---|
| D1 | каталог `$UPSTREAM_DIR/skills/<имя>` существует | `апстрим` |
| D2 | в `description:` есть `(gstack)`, без учета регистра | `метка gstack` |
| D3 | каталог `$OVERLAY_SKILLS_DIR/<имя>` существует | `уже в overlay` |
| D4 | имя перечислено в `CAPTURE_DENY` | `профиль` |

- [ ] **Step 1: Написать падающие тесты**

Дописать в `overlay/tests/cases/capture.sh`:

```bash
test_capture_denies_upstream() {
  _mk_skill "$HOME/.claude/skills" researcher 'что угодно'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    researcher: апстрим'
}

test_capture_denies_gstack_mark() {
  _mk_skill "$HOME/.claude/skills" my-browse 'Fast headless browser. (gstack)'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    my-browse: метка gstack'
}

test_capture_denies_already_in_overlay() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  _mk_skill "$HARNESS_OVERLAY_SKILLS" mine 'личный скилл'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    mine: уже в overlay'
}

test_capture_denies_by_profile() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  write_profile 'CAPTURE_DENY="mine other"'
  run_ok capture
  assert_contains "$SB/out.log" 'DENY    mine: профиль'
}

test_capture_skips_entry_without_skill_md() {
  mkdir -p "$HOME/.claude/skills/not-a-skill"
  printf 'x\n' > "$HOME/.claude/skills/not-a-skill/readme.txt"
  run_ok capture
  assert_contains "$SB/out.log" 'SKIP    not-a-skill: нет SKILL.md'
}

test_capture_plan_writes_nothing() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_ok capture
  assert_contains "$SB/out.log" 'CAPTURE mine'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/mine"
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh capture`
Expected: 4 теста задачи 1 проходят, 6 новых падают — заглушка `run_capture` не печатает ни `DENY`, ни `SKIP`, ни `CAPTURE`. Итог: `passed: 4, failed: 6`.

- [ ] **Step 3: Заменить `capture.sh` целиком**

`overlay/lib/capture.sh`:

```bash
# Переезд скиллов с этой машины в overlay/skills/.
# Разовая операция: после нее источник истины - репозиторий, а не машина.
# Отбор - денилист, три правила из четырех засеваются автоматически.

# Значение description: из фронтматтера SKILL.md. Пусто, если фронтматтера нет.
skill_description() {
  awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    NR > 1 && $0 ~ /^---[[:space:]]*$/ { exit }
    /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }
  ' "$1"
}

# capture_decision <имя> <путь-к-SKILL.md> -> "capture" | "deny:<причина>"
capture_decision() {
  local name="$1" skill_md="$2" desc lower denied
  if [ -d "$UPSTREAM_DIR/skills/$name" ]; then
    printf 'deny:апстрим'; return 0
  fi
  desc="$(skill_description "$skill_md")"
  lower="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *"(gstack)"*) printf 'deny:метка gstack'; return 0 ;;
  esac
  if [ -d "$OVERLAY_SKILLS_DIR/$name" ]; then
    printf 'deny:уже в overlay'; return 0
  fi
  for denied in $CAPTURE_DENY; do
    if [ "$denied" = "$name" ]; then
      printf 'deny:профиль'; return 0
    fi
  done
  printf 'capture'
}

run_capture() {
  local mode="$1" root d name decision captured=0
  root="$(runtime_home "$CAPTURE_FROM")/skills"
  info "режим: capture $mode"
  info "источник: $root"
  if [ ! -d "$root" ]; then
    info "SKIP    нет каталога скиллов: $root"
    return 0
  fi
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    if [ ! -f "$d/SKILL.md" ]; then
      info "SKIP    $name: нет SKILL.md"
      continue
    fi
    decision="$(capture_decision "$name" "$d/SKILL.md")"
    if [ "$decision" != capture ]; then
      info "DENY    $name: ${decision#deny:}"
      continue
    fi
    info "CAPTURE $name"
    captured=$((captured + 1))
  done
  if [ "$mode" = plan ]; then
    info "это был plan: ничего не записано. Применить: overlay/harness.sh capture apply"
  fi
}
```

Порядок правил важен: D1 проверяется первым, потому что имя, совпавшее с апстримом, не должно попасть в слой ни при каких описаниях. D2 стоит раньше D3, чтобы причина в выводе называла настоящий источник скилла, а не факт, что он уже переехал.

- [ ] **Step 4: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh capture`
Expected: `passed: 10, failed: 0`.

- [ ] **Step 5: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 89, failed: 0` (83 + 6).

- [ ] **Step 6: Commit**

```bash
git add overlay/lib/capture.sh overlay/tests/cases/capture.sh
git commit -m "Добавлен отбор кандидатов переезда: денилист с автозасевом" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Запись, маркер происхождения и документация

**Files:**
- Modify: `overlay/lib/capture.sh`
- Modify: `overlay/README.md`
- Test: `overlay/tests/cases/capture.sh`

**Interfaces:**
- Consumes: `capture_decision`, `run_capture` из задачи 2; `info`, `warn` из `common.sh`.
- Produces: `capture_one <имя> <каталог-источника>` — копирует скилл в `$OVERLAY_SKILLS_DIR/<имя>`, исключая файлы `.env`, и пишет маркер `.harness-origin`.

- [ ] **Step 1: Написать падающие тесты**

Дописать в `overlay/tests/cases/capture.sh`:

```bash
test_capture_apply_copies_whole_skill() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  mkdir -p "$HOME/.claude/skills/mine/scripts"
  printf 'echo hi\n' > "$HOME/.claude/skills/mine/scripts/run.sh"
  run_ok capture apply
  assert_contains "$SB/out.log" 'WROTE'
  assert_file "$HARNESS_OVERLAY_SKILLS/mine/SKILL.md"
  assert_file "$HARNESS_OVERLAY_SKILLS/mine/scripts/run.sh"
  assert_contains "$HARNESS_OVERLAY_SKILLS/mine/scripts/run.sh" 'echo hi'
}

test_capture_apply_skips_env_files() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  printf 'KEY=secret\n' > "$HOME/.claude/skills/mine/.env"
  mkdir -p "$HOME/.claude/skills/mine/scripts"
  printf 'KEY=secret\n' > "$HOME/.claude/skills/mine/scripts/.env"
  run_ok capture apply
  assert_file "$HARNESS_OVERLAY_SKILLS/mine/SKILL.md"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/mine/.env"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/mine/scripts/.env"
  assert_contains "$SB/out.log" 'пропущен .env'
}

test_capture_apply_writes_origin_marker() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  run_ok capture apply
  assert_file "$HARNESS_OVERLAY_SKILLS/mine/.harness-origin"
  assert_contains "$HARNESS_OVERLAY_SKILLS/mine/.harness-origin" 'capture '
}

test_capture_apply_is_idempotent() {
  _mk_skill "$HOME/.claude/skills" mine 'личный скилл'
  run_ok capture apply
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_ok capture apply
  assert_contains "$SB/out.log" 'DENY    mine: уже в overlay'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh capture`
Expected: 10 тестов задач 1–2 проходят, 4 новых падают — `capture apply` пока только печатает `CAPTURE`, ничего не копируя. Итог: `passed: 10, failed: 4`.

- [ ] **Step 3: Добавить `capture_one` в `capture.sh`**

Дописать в `overlay/lib/capture.sh` ПЕРЕД функцией `run_capture`:

```bash
# Скопировать скилл в слой. Файлы .env не переезжают: overlay/skills
# коммитится в git, а README апстрима велит класть туда ключи.
capture_one() {
  local name="$1" src="$2" dst="$OVERLAY_SKILLS_DIR/$name" f rel
  mkdir -p "$dst"
  while IFS= read -r f; do
    if [ "$(basename "$f")" = .env ]; then
      warn "в $name пропущен .env: секреты не переезжают"
      continue
    fi
    rel="${f#"$src"}"
    mkdir -p "$(dirname "$dst/$rel")"
    cp -p "$f" "$dst/$rel"
  done < <(find "$src" -type f)
  printf 'capture %s %s\n' "${HOSTNAME:-unknown}" "$(date +%Y-%m-%d)" > "$dst/.harness-origin"
  info "WROTE   $dst"
}
```

Каталог-источник приходит из глиба `"$root"/*/` и всегда заканчивается слэшем, поэтому `${f#"$src"}` дает путь относительно скилла без ведущего слэша.

- [ ] **Step 4: Подключить запись в `run_capture`**

В `overlay/lib/capture.sh`, в функции `run_capture`, заменить блок

```bash
    info "CAPTURE $name"
    captured=$((captured + 1))
```

на

```bash
    info "CAPTURE $name"
    captured=$((captured + 1))
    if [ "$mode" = apply ]; then
      capture_one "$name" "$d"
    fi
```

и заменить хвост функции

```bash
  if [ "$mode" = plan ]; then
    info "это был plan: ничего не записано. Применить: overlay/harness.sh capture apply"
  fi
```

на

```bash
  if [ "$mode" = plan ]; then
    info "это был plan: ничего не записано. Применить: overlay/harness.sh capture apply"
  else
    info "переехало скиллов: $captured"
  fi
```

- [ ] **Step 5: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh capture`
Expected: `passed: 14, failed: 0`.

- [ ] **Step 6: Вывести `overlay/skills/` из-под тестов гигиены**

Тесты `test_repo_no_yo_letters` и `test_repo_lf_only` сканируют весь `overlay/`. Пока слой
состоял только из того, что мы написали сами, это было верно. С этой задачи в
`overlay/skills/` попадает чужой текст: переехавшие скиллы пишет не харнес, и требовать от
них конвенции репозитория (нет буквы U+0451, окончания LF) нельзя — первый же переезд
скилла с русским текстом уронил бы прогон. Проверки остаются для файлов, которые мы
авторствуем.

В `overlay/tests/cases/repo.sh` заменить `test_repo_no_yo_letters` целиком на:

```bash
# Конвенция апстрима: без букв U+0451 и U+0401. Байты заданы escape-последовательностями,
# чтобы сам тест не содержал запрещенных букв. overlay/skills исключен: там лежит чужой
# текст - переехавшие и синканные скиллы, их конвенции репозитория не касаются.
test_repo_no_yo_letters() {
  local hits
  hits="$(grep -rlI -e $'\xd1\x91' -e $'\xd0\x81' "$OVERLAY_DIR" \
            --exclude-dir=.build --exclude-dir=skills || true)"
  [ -z "$hits" ] || fail "буква U+0451/U+0401 в файлах:"$'\n'"$hits"
}
```

и `test_repo_lf_only` целиком на:

```bash
test_repo_lf_only() {
  local f hits=""
  while IFS= read -r f; do
    if has_cr "$f"; then hits="$hits"$'\n'"$f"; fi
  done < <(find "$OVERLAY_DIR" -type f \
             -not -path '*/.build/*' -not -path '*/skills/*' -not -name 'profile.env')
  [ -z "$hits" ] || fail "CRLF в файлах:$hits"
}
```

Число тестов не меняется: обе функции переписаны, а не добавлены.

- [ ] **Step 7: Дописать раздел в `README.md`**

В `overlay/README.md`, сразу после раздела «Что ставится» и перед разделом «Как это устроено», вставить:

```markdown
## Переезд своих скиллов

`overlay/skills/` наполняется не руками, а командой:

```bash
overlay/harness.sh capture         # показать, что переедет и что отклонено
overlay/harness.sh capture apply   # перенести в overlay/skills/
```

Это разовая операция: после нее источник истины — репозиторий, и правки делаются в нем.
Повторный запуск ничего не переносит заново.

Отклоняются автоматически: скиллы, чье имя совпадает с апстримным (иначе `git pull
upstream` перестал бы на них влиять), помеченные `(gstack)` в описании, и уже лежащие в
`overlay/skills/`. Остальное можно выписать руками в `CAPTURE_DENY`.

Файлы `.env` не переезжают никогда: слой коммитится в git.
```

- [ ] **Step 8: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 94, failed: 0` (90 + 4). Тесты гигиены должны остаться зелеными: в новом тексте README нет буквы U+0451, окончания строк LF, а `overlay/skills/` из них теперь исключен.

- [ ] **Step 9: Commit**

```bash
git add overlay/lib/capture.sh overlay/README.md overlay/tests/cases/repo.sh \
        overlay/tests/cases/capture.sh
git commit -m "Добавлена запись переезда: копирование без .env и маркер происхождения" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Переезд на машине владельца

Задача не для субагента: она меняет содержимое репозитория на основании того, что реально стоит на машине, и требует ревью списка владельцем. Выполняет основной агент вместе с владельцем.

- [ ] **Step 1: Показать список**

Run: `overlay/harness.sh capture`

Ожидается: примерно 11 строк `DENY ...: апстрим`, около 50 строк `DENY ...: метка gstack`, `SKIP    README.md: нет SKILL.md` и несколько строк `CAPTURE`. Среди кандидатов ожидаются `goal`, `learn`, `product-editor`, `uniqore-cpo`, `uniqore-desktop-test` и спорные `gstack-upgrade`, `open-gstack-browser`, `setup-deploy`.

- [ ] **Step 2: Владелец решает по спорным**

Показать владельцу список `CAPTURE` целиком. То, что переезжать не должно, дописать в `CAPTURE_DENY` в `overlay/profile.env` и повторить Step 1, пока список не станет верным.

- [ ] **Step 3: Перенести — только после явного «ок» владельца**

Run: `overlay/harness.sh capture apply`

- [ ] **Step 4: Проверить дифф до коммита**

Run: `git status --short && git diff --stat`

Проверить вместе с владельцем: не попал ли в слой файл с секретом, не утащило ли скилл с бинарными вложениями неожиданного размера. Ни одного файла вне `overlay/skills/` в диффе быть не должно.

- [ ] **Step 5: Убедиться, что раскатка видит новые скиллы**

Run: `overlay/harness.sh plan`

Ожидается: переехавшие скиллы показаны как `new` для Codex и как `changed` для Claude Code. Именно `changed`, а не `same`: копия в слое несет файл `.harness-origin`, которого нет в установленной, и `skill_differs` это видит. Это нормально — следующий `apply` переставит скилл, прежняя копия уедет в бэкап, и дальше статус станет `same`.

- [ ] **Step 6: Коммит содержимого**

Сообщение коммита называет, что именно переехало.

---

## Проверка покрытия спека

| Требование спека | Задача |
|---|---|
| Грамматика `capture [plan|apply]` | 1, тесты `test_capture_mode_accepted`, `test_capture_apply_submode_accepted`, `test_capture_unknown_submode_fails` |
| `CAPTURE_FROM`, валидация | 1, тест `test_capture_bad_from_fails` |
| `CAPTURE_DENY` | 1 (ключ), 2 (правило D4, тест `test_capture_denies_by_profile`) |
| D1 апстрим | 2, `test_capture_denies_upstream` |
| D2 метка gstack, без учета регистра | 2, `test_capture_denies_gstack_mark` |
| D3 уже в overlay | 2, `test_capture_denies_already_in_overlay` |
| Запись без `SKILL.md` пропускается | 2, `test_capture_skips_entry_without_skill_md` |
| `plan` ничего не пишет | 2, `test_capture_plan_writes_nothing` |
| Скилл переезжает целиком | 3, `test_capture_apply_copies_whole_skill` |
| `.env` не переезжает, предупреждение | 3, `test_capture_apply_skips_env_files` |
| Маркер `.harness-origin` | 3, `test_capture_apply_writes_origin_marker` |
| Идемпотентность | 3, `test_capture_apply_is_idempotent` |
| Каталога скиллов нет — не ошибка | 2 (ветка `SKIP нет каталога скиллов`) |
| Переезд не трогает домашние каталоги | 1 (в `main` переезд не вызывает `commit_pending`), 2–3 (пишут только в `$OVERLAY_SKILLS_DIR`) |
| Обычные `plan` и `apply` не сломаны | 1, полный прогон в Step 8: все 79 прежних тестов остаются зелеными |
| Документация | 1 (`profile.example.env`), 3 (`README.md`) |
| Раскатка на машине владельца | 4 |

Сверх спека план вводит один пункт: вывод `overlay/skills/` из-под тестов гигиены (задача 3, Step 6). Спек этого не предусмотрел, но без этого первый же переезд скилла с русским текстом или с CRLF уронил бы прогон — конвенции репозитория написаны для файлов, которые мы авторствуем, а в `overlay/skills/` с этой задачи лежит чужое.
