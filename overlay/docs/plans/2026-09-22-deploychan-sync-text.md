# Синк deploychan, текстовая ветка — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Команда `overlay/harness.sh sync apply` тянет объявленные текстовые паки из MCP deploychan и кладет их в `overlay/skills/` как готовые `SKILL.md`.

**Architecture:** Третье действие рядом с `plan|apply` и `capture`. Разделение труда: Python делает сеть и JSON, bash делает диффы и запись. `overlay/lib/sync.py` рендерит пак в каталог сборки и печатает sha256; `overlay/lib/sync.sh` разбирает `overlay/sync.conf`, решает по состоянию и пишет. Bash не разбирает JSON вообще.

**Tech Stack:** bash >= 4.4 для ядра, Python 3 stdlib (`urllib`, `json`, `hashlib`) только для синка. Тесты — существующий раннер `overlay/tests/run.sh`, сеть заменяется фикстурой.

Спек: `overlay/docs/specs/2026-09-22-deploychan-sync-design.md`.

Софтовая ветка (клон объявленных репозиториев) — отдельный план поверх этого. Здесь реализуется только текстовая.

## Протокол MCP — проверено на живом сервере 2026-09-22

Не выводите это из документации, факты сняты запросами:

- Сервер **stateless**: `tools/call` работает без `initialize`, заголовок `Mcp-Session-Id` не выдается. Клиент — один POST на вызов.
- Ответ — `application/json`, не SSE, несмотря на заголовок `Accept`.
- `list_skills` возвращает `result.structuredContent.result` — список паков без поля `body`.
- `get_skill` возвращает `structuredContent` **не всегда**: у него этого ключа нет, и тело лежит в `result.content[0].text` строкой, которую надо разобрать как JSON.
- Неизвестный пак — **HTTP 200** с `result.isError == true` и текстом ошибки в `content[0].text`. JSON-RPC-ошибки сервер не отдает.
- Поле `reminder` бывает `null` (например у `x-content-advisor`). Поле `allowed_tools` пустое у всех паков.
- Во всех 10 описаниях каталога нет переводов строк и кавычек. Экранирование пишется как защита, а не как текущая необходимость.

Эндпоинт: `https://mcp.deploychan.webcam/mcp`.

## Global Constraints

- Все новые файлы — только внутри `overlay/`. Ни один файл апстрима не меняется, включая корневые `.gitignore` и `README.md`, `install.sh`, `skills/`, `global-config/`.
- Синк пишет только в `$OVERLAY_SKILLS_DIR` и в каталог сборки. Домашние каталоги рантаймов он не трогает ни в одном режиме.
- Режим `plan` не создает и не меняет ни одного файла вне каталога сборки.
- Ядро остается чистым bash: Python вызывается только из кода синка. `plan` и `apply` не должны зависеть от Python.
- Bash не разбирает JSON. Вся работа с JSON — в `sync.py`.
- Зависимости: bash >= 4.4, coreutils, `diff`, `sed`, `awk`, `find`, `cmp`, `jq`, плюс `python3` для синка.
- Новый код ошибки ровно один: `E_MCP`. Разбор `overlay/sync.conf` использует существующий `E_PROFILE` и называет файл и номер строки. Строки статуса начинаются с ASCII-токена: `SYNC`, `SKIP`, `WROTE`, `WARN`.
- Конвенция репозитория: в коммитимых файлах нет буквы U+0451 и U+0401. Проверка: `grep -rlI -e $'\xd1\x91' -e $'\xd0\x81' overlay --exclude-dir=.build --exclude-dir=skills`.
- Все текстовые файлы — с окончаниями LF. Наличие `\r` нельзя проверять через `grep $'\r'`: в Git Bash такой шаблон совпадает с каждой строкой. Только помощник `has_cr` из `tests/run.sh`.
- В конвейерах под `set -o pipefail` нельзя писать `producer | grep -q`: сначала сохранить вывод в переменную, потом `grep -q ... <<< "$var"`.
- Тесты не ходят в сеть. Каталог и паки берутся из фикстуры через `HARNESS_MCP_FIXTURE`.
- Шелл — Git Bash. Не PowerShell и не `C:\Windows\System32\bash.exe` (заглушка WSL).
- Полный прогон занимает несколько минут: задавайте командам щедрый таймаут (например 900000 мс) и ждите завершения в форграунде. Не ставьте Monitor и не ждите его — на этом уже зависали три агента.
- Настоящий `overlay/harness.sh` против своего реального `HOME` не запускать. Проверять только через `bash overlay/tests/run.sh`.
- Сообщения коммитов — на русском, в стиле апстрима, с трейлером `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`. Трейлер писать буквально, не подставляя свое имя модели.

## Карта файлов

| Файл | Ответственность | Задача |
|---|---|---|
| `overlay/lib/sync.py` | сеть, JSON, рендер пака, sha256 | 2, 3 |
| `overlay/lib/sync.sh` | разбор `sync.conf`, состояния, запись | 1, 4, 5 |
| `overlay/harness.sh` | грамматика третьего действия | 1 |
| `overlay/sync.conf` | состав дистрибутива | 1 |
| `overlay/README.md` | раздел про синк | 5 |
| `overlay/tests/cases/sync.sh` | тесты синка | 1-5 |
| `overlay/tests/fixtures/catalog.json` | каталог и паки для тестов | 2 |

Состояние на входе: `bash overlay/tests/run.sh` дает `passed: 99, failed: 0`.

---

### Task 1: Грамматика `sync` и разбор `sync.conf`

**Files:**
- Modify: `overlay/harness.sh` (комментарий-заголовок, `usage`, `main`)
- Create: `overlay/lib/sync.sh`, `overlay/sync.conf`
- Test: `overlay/tests/cases/sync.sh`

**Interfaces:**
- Consumes: `die`, `info`, `warn` из `common.sh`; `check_prereqs`, `load_profile`, `validate_profile` из `detect.sh`; `assert_profile_kept_internals`, `reset_build_dir` из `harness.sh`.
- Produces:
  - Грамматика `harness.sh sync [plan|apply]`, по умолчанию `plan`, не более двух аргументов.
  - `SYNC_CONF` — путь к файлу состава, `${HARNESS_SYNC_CONF:-$OVERLAY_DIR/sync.conf}`.
  - `sync_entries` — печатает по строке на объявленный пак в виде `<вид> <id> <поле3> <поле4>`, где вид `text` или `software`. Для текстового пака поля 3 и 4 — дефисы.
  - `run_sync <plan|apply>` — в этой задаче печатает разобранный состав. Задачи 3-5 наращивают ее.

- [ ] **Step 1: Написать падающие тесты**

Создать `overlay/tests/cases/sync.sh`:

```bash
_write_sync_conf() {
  printf '%s\n' "$@" > "$HARNESS_SYNC_CONF"
}

test_sync_mode_accepted() {
  _write_sync_conf '# пусто'
  run_ok sync
  assert_contains "$SB/out.log" 'режим: sync plan'
}

test_sync_apply_submode_accepted() {
  _write_sync_conf '# пусто'
  run_ok sync apply
  assert_contains "$SB/out.log" 'режим: sync apply'
}

test_sync_rejects_extra_arg() {
  _write_sync_conf '# пусто'
  if run_harness sync apply extra; then fail "лишний аргумент должен падать"; fi
}

test_sync_conf_missing_is_error() {
  rm -f "$HARNESS_SYNC_CONF"
  run_fail E_PROFILE sync
}

test_sync_conf_parses_text_and_software() {
  _write_sync_conf '# комментарий' '' 'x-content-advisor' 'zaebal  https://example.com/z.git  v1.0'
  run_ok sync
  assert_contains "$SB/out.log" 'ENTRY   text x-content-advisor'
  assert_contains "$SB/out.log" 'ENTRY   software zaebal https://example.com/z.git v1.0'
}

test_sync_conf_bad_field_count() {
  _write_sync_conf 'x-content-advisor' 'zaebal https://example.com/z.git'
  run_fail E_PROFILE sync
  assert_contains "$SB/out.log" 'строка 2'
}
```

Тестам нужны две переменные песочницы, которых в раннере еще нет. Это единственная правка `overlay/tests/run.sh` во всем плане, и она делается здесь.

В `overlay/tests/run.sh`, в функции `new_sandbox`, после строки `export HARNESS_TS="20260101-000000"` добавить:

```bash
  export HARNESS_SYNC_CONF="$SB/sync.conf"
  export HARNESS_MCP_FIXTURE="$REPO_DIR/overlay/tests/fixtures/catalog.json"
```

и в списке `mkdir -p` ничего менять не нужно.

- [ ] **Step 2: Запустить тесты и убедиться, что они падают**

Run: `bash overlay/tests/run.sh sync`
Expected: 6 тестов, падают все шесть — режим `sync` пока не распознается, `harness.sh` выходит с кодом 2. Итог: `passed: 0, failed: 6`.

- [ ] **Step 3: Написать `overlay/lib/sync.sh`**

```bash
# Синк каталога deploychan. Сеть и JSON делает sync.py, bash решает и пишет.

SYNC_CONF="${HARNESS_SYNC_CONF:-$OVERLAY_DIR/sync.conf}"
MCP_URL="${HARNESS_MCP_URL:-https://mcp.deploychan.webcam/mcp}"

# Разобранный состав дистрибутива, по строке на пак:
#   text <id> - -
#   software <id> <url> <ревизия>
sync_entries() {
  [ -f "$SYNC_CONF" ] ||
    die "E_PROFILE нет файла состава: $SYNC_CONF. Создайте его и перечислите паки."
  awk -v conf="$SYNC_CONF" '
    { sub(/\r$/, "") }
    /^[[:space:]]*(#|$)/ { next }
    NF == 1 { printf "text %s - -\n", $1; next }
    NF == 3 { printf "software %s %s %s\n", $1, $2, $3; next }
    {
      printf "E_PROFILE %s строка %d: нужно 1 поле (текстовый пак) или 3 (софтовый), а их %d\n",
             conf, FNR, NF > "/dev/stderr"
      exit 1
    }
  ' "$SYNC_CONF"
}

run_sync() {
  local mode="$1" entries rc=0 kind id url rev
  info "режим: sync $mode"
  entries="$(sync_entries)" || rc=$?
  [ "$rc" -eq 0 ] || exit 1
  while read -r kind id url rev; do
    [ -n "$kind" ] || continue
    info "ENTRY   $kind $id $url $rev"
  done <<< "$entries"
}
```

Вывод `ENTRY` с дефисами вместо пустых полей нужен, чтобы `read -r` всегда получал четыре поля и не склеивал столбцы. Для текстового пака строка выглядит как `ENTRY   text x-content-advisor - -`, и тест ищет ее префикс.

Задача 3 заменяет вывод `ENTRY` строками `SYNC` и переписывает этот тест.

Ошибку разбора `sync_entries` печатает сама, с кодом `E_PROFILE`. Состав собирается в переменную заранее, а не через `< <(...)`: в подстановке процесса код возврата теряется, и кривая строка `sync.conf` прошла бы незамеченной.

- [ ] **Step 4: Добавить грамматику в `harness.sh`**

Заменить строки-комментарии 3-4 на три:

```bash
# Использование: overlay/harness.sh [plan|apply]            (по умолчанию plan)
#                overlay/harness.sh capture [plan|apply]    (по умолчанию plan)
#                overlay/harness.sh sync [plan|apply]       (по умолчанию plan)
```

Заменить `usage` целиком на:

```bash
usage() {
  printf 'Usage: %s [plan|apply]\n' "$0" >&2
  printf '       %s capture [plan|apply]\n' "$0" >&2
  printf '       %s sync [plan|apply]\n' "$0" >&2
}
```

В `main`, в первом `case`, после ветки `capture)` добавить:

```bash
    sync)
      [ $# -le 2 ] || { usage; exit 2; }
      action=sync; mode="${2:-plan}"
      ;;
```

и после блока `if [ "$action" = capture ]; then ... fi` добавить:

```bash
  if [ "$action" = sync ]; then
    reset_build_dir
    run_sync "$mode"
    return 0
  fi
```

Синк вызывает `reset_build_dir`, потому что рендерит паки в каталог сборки. `detect_runtimes` ему не нужен: домашних каталогов он не касается.

- [ ] **Step 5: Создать `overlay/sync.conf`**

```
# Состав дистрибутива: какие паки каталога deploychan попадают в overlay/skills.
# Одно поле - текстовый пак, идентификатор из каталога.
# Три поля - софтовый пак: идентификатор, URL репозитория, закрепленная ревизия.
# Софтовая ветка еще не реализована, такие строки пока только разбираются.

x-content-advisor
```

- [ ] **Step 6: Запустить тесты и убедиться, что они проходят**

Run: `bash overlay/tests/run.sh sync`
Expected: `passed: 6, failed: 0`.

- [ ] **Step 7: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 105, failed: 0` (99 прежних + 6 новых). Прежние тесты не должны сломаться: грамматика `plan`/`apply`/`capture` сохранена.

- [ ] **Step 8: Commit**

```bash
git add overlay/harness.sh overlay/lib/sync.sh overlay/sync.conf \
        overlay/tests/run.sh overlay/tests/cases/sync.sh
git commit -m "Добавлена грамматика overlay/harness.sh sync и разбор состава дистрибутива" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Клиент к MCP

**Files:**
- Create: `overlay/lib/sync.py`, `overlay/tests/fixtures/catalog.json`
- Test: `overlay/tests/cases/sync.sh`

**Interfaces:**
- Consumes: ничего из bash — скрипт самостоятелен.
- Produces: `python3 overlay/lib/sync.py catalog <endpoint>` печатает по идентификатору пака на строку. Ошибки идут в stderr строкой, начинающейся с `E_MCP`, код возврата 1.
- Формат фикстуры: JSON-объект `{"list_skills": [<паки без body>], "get_skill": {"<id>": <полный пак>}}`. Если задана `HARNESS_MCP_FIXTURE`, скрипт читает ее вместо сети.

- [ ] **Step 1: Написать фикстуру**

`overlay/tests/fixtures/catalog.json`:

```json
{
  "list_skills": [
    {"id": "alpha", "name": "Alpha Pack", "summary": "Первый тестовый пак.", "tags": ["one", "two"], "author": "kisa", "recommended": true, "base": false},
    {"id": "beta", "name": "Beta Pack", "summary": "Второй тестовый пак.", "tags": ["three"], "author": "kisa", "recommended": false, "base": false}
  ],
  "get_skill": {
    "alpha": {
      "id": "alpha",
      "name": "Alpha Pack",
      "summary": "Первый тестовый пак.",
      "reminder": "Помни про альфу.",
      "tags": ["one", "two"],
      "allowed_tools": [],
      "triggers": ["запусти альфу", "нужна альфа"],
      "author": "kisa",
      "recommended": true,
      "base": false,
      "body": "# Alpha Pack\n\nТело первого пака.\n"
    },
    "beta": {
      "id": "beta",
      "name": "Beta Pack",
      "summary": "Второй тестовый пак с \"кавычками\" и\nпереводом строки.",
      "reminder": null,
      "tags": ["three"],
      "allowed_tools": [],
      "triggers": [],
      "author": "kisa",
      "recommended": false,
      "base": false,
      "body": "# Beta Pack\n\nТело второго пака.\n"
    }
  }
}
```

Пак `beta` намеренно несет `reminder: null`, пустые `triggers`, кавычки и перевод строки в описании: это те формы, на которых выдуманный код ломается.

- [ ] **Step 2: Написать падающие тесты**

Дописать в `overlay/tests/cases/sync.sh`:

```bash
test_sync_py_catalog_from_fixture() {
  local out
  out="$(python3 "$OVERLAY_DIR/lib/sync.py" catalog unused 2>&1)" || fail "sync.py упал: $out"
  assert_eq "$out" 'alpha'$'\n''beta'
}

test_sync_py_unknown_pack_is_e_mcp() {
  local out rc=0
  out="$(python3 "$OVERLAY_DIR/lib/sync.py" render unused nosuch "$SB/out" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] || fail "неизвестный пак должен давать ненулевой код"
  case "$out" in
    E_MCP*) ;;
    *) fail "ожидался E_MCP, получено: $out" ;;
  esac
}
```

- [ ] **Step 3: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh sync`
Expected: 6 тестов задачи 1 проходят, 2 новых падают с `can't open file ... sync.py`. Итог: `passed: 6, failed: 2`.

- [ ] **Step 4: Написать `overlay/lib/sync.py`**

```python
#!/usr/bin/env python3
"""Клиент к MCP deploychan. Вызывается только режимом sync.

Сервер stateless: tools/call работает без initialize, сессия не нужна.
Формы ответа у инструментов разные, поэтому обе обрабатываются здесь,
а bash про JSON ничего не знает.
"""
import hashlib
import json
import os
import sys
import urllib.request

TIMEOUT = 30


class McpError(Exception):
    pass


def _from_fixture(tool, arguments):
    path = os.environ.get("HARNESS_MCP_FIXTURE", "")
    if not path:
        return None
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    if tool == "get_skill":
        packs = data.get("get_skill") or {}
        skill_id = arguments["skill_id"]
        if skill_id not in packs:
            raise McpError("пак не найден: %s" % skill_id)
        return packs[skill_id]
    if tool not in data:
        raise McpError("в фикстуре нет инструмента: %s" % tool)
    return data[tool]


def call(endpoint, tool, arguments):
    fixture = _from_fixture(tool, arguments)
    if fixture is not None:
        return fixture
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            body = json.load(response)
    except Exception as exc:
        raise McpError("сервер недоступен: %s" % exc)
    result = body.get("result")
    if result is None:
        raise McpError("неожиданный ответ сервера: нет result")
    if result.get("isError"):
        texts = [item.get("text", "") for item in result.get("content") or []]
        raise McpError(" ".join(texts).strip() or "инструмент вернул ошибку")
    if "structuredContent" in result:
        return result["structuredContent"]["result"]
    content = result.get("content") or []
    if not content:
        raise McpError("пустой ответ инструмента")
    return json.loads(content[0]["text"])


def one_line(value):
    return " ".join((value or "").split())


def yaml_string(value):
    text = one_line(value).replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % text


def yaml_list(values):
    return "[%s]" % ", ".join(yaml_string(item) for item in values or [])


def render(pack):
    lines = [
        "---",
        "name: %s" % pack["id"],
        "description: %s" % yaml_string(pack.get("summary")),
        "metadata:",
        "  hermes:",
        "    tags: %s" % yaml_list(pack.get("tags")),
    ]
    extra = []
    if pack.get("triggers"):
        extra.append("    triggers: %s" % yaml_list(pack["triggers"]))
    if pack.get("reminder"):
        extra.append("    reminder: %s" % yaml_string(pack["reminder"]))
    if extra:
        lines.append("  deploychan:")
        lines.extend(extra)
    lines.append("---")
    body = (pack.get("body") or "").replace("\r\n", "\n").rstrip("\n")
    return "\n".join(lines) + "\n" + body + "\n"


def cmd_catalog(endpoint):
    for item in call(endpoint, "list_skills", {}):
        print(item["id"])


def cmd_render(endpoint, skill_id, outdir):
    pack = call(endpoint, "get_skill", {"skill_id": skill_id})
    text = render(pack)
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, "SKILL.md")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(hashlib.sha256(text.encode("utf-8")).hexdigest())


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: sync.py <catalog|render> <endpoint> [id outdir]\n")
        return 2
    command, endpoint = argv[1], argv[2]
    try:
        if command == "catalog":
            cmd_catalog(endpoint)
        elif command == "render":
            if len(argv) < 5:
                sys.stderr.write("usage: sync.py render <endpoint> <id> <outdir>\n")
                return 2
            cmd_render(endpoint, argv[3], argv[4])
        else:
            sys.stderr.write("E_MCP неизвестная подкоманда: %s\n" % command)
            return 2
    except McpError as exc:
        sys.stderr.write("E_MCP %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 5: Добавить `python3` в пререквизиты синка**

В `overlay/lib/sync.sh`, в начало `run_sync`, сразу после `info "режим: sync $mode"`, добавить:

```bash
  command -v python3 >/dev/null 2>&1 ||
    die "E_PREREQ не найден python3. Он нужен только синку; plan и apply работают без него."
```

- [ ] **Step 6: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh sync`
Expected: `passed: 8, failed: 0`.

- [ ] **Step 7: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 107, failed: 0` (105 + 2).

- [ ] **Step 8: Commit**

```bash
git add overlay/lib/sync.py overlay/lib/sync.sh overlay/tests/fixtures/catalog.json \
        overlay/tests/cases/sync.sh
git commit -m "Добавлен клиент к MCP deploychan на Python stdlib" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Материализация текстового пака

**Files:**
- Modify: `overlay/lib/sync.sh`
- Test: `overlay/tests/cases/sync.sh`

**Interfaces:**
- Consumes: `python3 overlay/lib/sync.py render <endpoint> <id> <outdir>` из задачи 2 — пишет `<outdir>/SKILL.md` и печатает sha256 в stdout.
- Produces: `sync_render <id>` — рендерит пак в `$BUILD_DIR/sync/<id>/`, печатает sha256; `sync_write <id> <hash>` — копирует отрендеренное в `$OVERLAY_SKILLS_DIR/<id>/` и пишет маркер.

- [ ] **Step 1: Написать падающие тесты**

Дописать в `overlay/tests/cases/sync.sh`:

```bash
test_sync_materializes_text_pack() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  assert_file "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'name: alpha'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'description: "Первый тестовый пак."'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'tags: ["one", "two"]'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'Тело первого пака.'
}

test_sync_puts_triggers_under_deploychan() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" '  deploychan:'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'triggers: ["запусти альфу", "нужна альфа"]'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'reminder: "Помни про альфу."'
}

test_sync_normalizes_summary_and_skips_null_reminder() {
  _write_sync_conf 'beta'
  run_ok sync apply
  assert_contains "$HARNESS_OVERLAY_SKILLS/beta/SKILL.md" 'description: "Второй тестовый пак с \"кавычками\" и переводом строки."'
  assert_not_contains "$HARNESS_OVERLAY_SKILLS/beta/SKILL.md" 'reminder:'
  assert_not_contains "$HARNESS_OVERLAY_SKILLS/beta/SKILL.md" 'triggers:'
}

test_sync_writes_origin_marker() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  assert_file "$HARNESS_OVERLAY_SKILLS/alpha/.harness-origin"
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/.harness-origin" 'deploychan:alpha sha256:'
}

test_sync_plan_writes_nothing() {
  _write_sync_conf 'alpha'
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_ok sync
  assert_contains "$SB/out.log" 'SYNC    alpha: new'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
  assert_no_path "$HARNESS_OVERLAY_SKILLS/alpha"
}
```

Заодно тест задачи 1 `test_sync_conf_parses_text_and_software` заменяется целиком:

```bash
test_sync_conf_parses_text_and_software() {
  _write_sync_conf '# комментарий' '' 'alpha' 'zaebal  https://example.com/z.git  v1.0'
  run_ok sync
  assert_contains "$SB/out.log" 'SYNC    alpha: new'
  assert_contains "$SB/out.log" 'SYNC    zaebal: софт, ревизия v1.0'
}
```

Причина: вывод `ENTRY` был временной диагностикой задачи 1, а объявленный в нем текстовый пак `x-content-advisor` отсутствует в фикстуре, и после задачи 3 его рендер дал бы `E_MCP` вместо прохождения теста.

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh sync`
Expected: 7 тестов задач 1-2 проходят, 5 новых и переписанный `test_sync_conf_parses_text_and_software` падают — синк пока только печатает состав. Итог: `passed: 7, failed: 6`.

- [ ] **Step 3: Добавить рендер и запись в `sync.sh`**

Дописать в `overlay/lib/sync.sh` перед `run_sync`:

```bash
# Отрендерить пак в каталог сборки. Печатает sha256 содержимого.
sync_render() {
  local id="$1"
  python3 "$OVERLAY_DIR/lib/sync.py" render "$MCP_URL" "$id" "$BUILD_DIR/sync/$id"
}

# Перенести отрендеренное в слой и записать маркер.
sync_write() {
  local id="$1" hash="$2" dst="$OVERLAY_SKILLS_DIR/$id"
  mkdir -p "$dst"
  cp "$BUILD_DIR/sync/$id/SKILL.md" "$dst/SKILL.md"
  printf 'deploychan:%s sha256:%s %s\n' "$id" "$hash" "$(date +%Y-%m-%d)" > "$dst/.harness-origin"
  info "WROTE   $dst"
}
```

- [ ] **Step 4: Научить `run_sync` обрабатывать текстовые паки**

Заменить тело цикла в `run_sync`. Функция целиком:

```bash
run_sync() {
  local mode="$1" entries rc=0 kind id url rev hash
  info "режим: sync $mode"
  command -v python3 >/dev/null 2>&1 ||
    die "E_PREREQ не найден python3. Он нужен только синку; plan и apply работают без него."
  entries="$(sync_entries)" || rc=$?
  [ "$rc" -eq 0 ] || exit 1
  while read -r kind id url rev; do
    [ -n "$kind" ] || continue
    if [ "$kind" != text ]; then
      info "SYNC    $id: софт, ревизия $rev"
      continue
    fi
    hash="$(sync_render "$id")"
    info "SYNC    $id: new"
    if [ "$mode" = apply ]; then
      sync_write "$id" "$hash"
    fi
  done <<< "$entries"
}
```

Статус пока всегда `new`: состояния появляются в задаче 4. Софтовые паки только упоминаются — их ветка в отдельном плане.

- [ ] **Step 5: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh sync`
Expected: `passed: 13, failed: 0`.

- [ ] **Step 6: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 112, failed: 0` (107 + 5).

- [ ] **Step 7: Commit**

```bash
git add overlay/lib/sync.sh overlay/tests/cases/sync.sh
git commit -m "Добавлена материализация текстовых паков в overlay/skills" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Состояния и конфликты

**Files:**
- Modify: `overlay/lib/sync.sh`
- Test: `overlay/tests/cases/sync.sh`

**Interfaces:**
- Consumes: `sync_render`, `sync_write` из задачи 3.
- Produces: `sync_state <id> <hash>` — печатает одно слово: `new`, `same`, `updated`, `edited` или `foreign`.

Таблица состояний из спека:

| Каталог `<id>` в слое | Маркер | Файл против маркера | Новый файл против диска | Состояние |
|---|---|---|---|---|
| нет | — | — | — | `new` |
| есть | не `deploychan:<id>` или отсутствует | — | — | `foreign` |
| есть | `deploychan:<id>` | совпал | совпал | `same` |
| есть | `deploychan:<id>` | совпал | отличается | `updated` |
| есть | `deploychan:<id>` | разошелся | — | `edited` |

Пишутся только `new` и `updated`. `same` не трогается, `edited` и `foreign` показываются и не перезаписываются.

- [ ] **Step 1: Написать падающие тесты**

Дописать в `overlay/tests/cases/sync.sh`:

```bash
test_sync_second_run_is_same() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: same'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
}

test_sync_updates_when_catalog_changed() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  local fixture="$SB/catalog.json"
  sed 's/Тело первого пака./Тело первого пака, версия два./' \
    "$REPO_DIR/overlay/tests/fixtures/catalog.json" > "$fixture"
  export HARNESS_MCP_FIXTURE="$fixture"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: updated'
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'версия два'
}

test_sync_does_not_overwrite_edited_file() {
  _write_sync_conf 'alpha'
  run_ok sync apply
  printf 'МОЯ ПРАВКА\n' >> "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  local before; before="$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: edited'
  assert_eq "$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")" "$before"
  assert_contains "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md" 'МОЯ ПРАВКА'
}

test_sync_does_not_touch_foreign_skill() {
  mkdir -p "$HARNESS_OVERLAY_SKILLS/alpha"
  printf -- '---\nname: alpha\ndescription: мой скилл\n---\nМОЕ ТЕЛО\n' \
    > "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md"
  printf 'capture DESKTOP 2026-09-21\n' > "$HARNESS_OVERLAY_SKILLS/alpha/.harness-origin"
  _write_sync_conf 'alpha'
  local before; before="$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")"
  run_ok sync apply
  assert_contains "$SB/out.log" 'SYNC    alpha: foreign'
  assert_eq "$(cksum < "$HARNESS_OVERLAY_SKILLS/alpha/SKILL.md")" "$before"
}
```

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh sync`
Expected: 13 тестов задач 1-3 проходят, 4 новых падают — статус пока всегда `new`, и `sync_write` перезаписывает что угодно. Итог: `passed: 13, failed: 4`.

- [ ] **Step 3: Добавить `sync_state` в `sync.sh`**

Дописать в `overlay/lib/sync.sh` перед `run_sync`:

```bash
# Состояние пака в слое относительно свежеотрендеренного.
# Печатает одно слово: new | foreign | same | updated | edited.
sync_state() {
  local id="$1" hash="$2" dst="$OVERLAY_SKILLS_DIR/$id" marker recorded actual
  if [ ! -d "$dst" ]; then printf 'new'; return 0; fi
  marker="$dst/.harness-origin"
  if [ ! -f "$marker" ] || ! grep -qF "deploychan:$id " "$marker"; then
    printf 'foreign'; return 0
  fi
  recorded="$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^sha256:/) { sub(/^sha256:/, "", $i); print $i; exit } }' "$marker")"
  actual="$(sync_file_hash "$dst/SKILL.md")"
  if [ "$recorded" != "$actual" ]; then printf 'edited'; return 0; fi
  if [ "$recorded" = "$hash" ]; then printf 'same'; else printf 'updated'; fi
}
```

Хэш лежащего на диске файла считает тот же Python, чтобы алгоритм был один. Дописать туда же:

```bash
sync_file_hash() {
  python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}
```

- [ ] **Step 4: Научить `run_sync` показывать состояние и дифф**

Заменить `run_sync` целиком:

```bash
run_sync() {
  local mode="$1" entries rc=0 kind id url rev hash state dst
  info "режим: sync $mode"
  command -v python3 >/dev/null 2>&1 ||
    die "E_PREREQ не найден python3. Он нужен только синку; plan и apply работают без него."
  entries="$(sync_entries)" || rc=$?
  [ "$rc" -eq 0 ] || exit 1
  while read -r kind id url rev; do
    [ -n "$kind" ] || continue
    if [ "$kind" != text ]; then
      info "SYNC    $id: софт, ревизия $rev"
      continue
    fi
    hash="$(sync_render "$id")"
    state="$(sync_state "$id" "$hash")"
    info "SYNC    $id: $state"
    dst="$OVERLAY_SKILLS_DIR/$id"
    case "$state" in
      new)
        diff -u /dev/null "$BUILD_DIR/sync/$id/SKILL.md" || true
        if [ "$mode" = apply ]; then sync_write "$id" "$hash"; fi
        ;;
      updated)
        diff -u "$dst/SKILL.md" "$BUILD_DIR/sync/$id/SKILL.md" || true
        if [ "$mode" = apply ]; then sync_write "$id" "$hash"; fi
        ;;
      edited)
        diff -u "$dst/SKILL.md" "$BUILD_DIR/sync/$id/SKILL.md" || true
        warn "$id правили руками, не перезаписываю. Удалите каталог и синкните заново, чтобы принять обновление."
        ;;
      foreign)
        warn "$id в слое пришел не из синка, не трогаю. Переименуйте свой скилл или уберите пак из $SYNC_CONF."
        ;;
    esac
  done <<< "$entries"
  if [ "$mode" = plan ]; then
    info "это был plan: ничего не записано. Применить: overlay/harness.sh sync apply"
  fi
}
```

Запись обернута в полный `if`, а не в `[ ... ] && sync_write`: короткая форма стоит последней в ветке `case`, и при `mode = plan` она вернула бы 1, что под `set -e` уронило бы синк.

- [ ] **Step 5: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh sync`
Expected: `passed: 17, failed: 0`.

- [ ] **Step 6: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 116, failed: 0` (112 + 4).

- [ ] **Step 7: Commit**

```bash
git add overlay/lib/sync.sh overlay/tests/cases/sync.sh
git commit -m "Добавлены состояния синка: same, updated, edited, foreign" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Необъявленные паки, сетевые ошибки, документация

**Files:**
- Modify: `overlay/lib/sync.sh`, `overlay/README.md`
- Test: `overlay/tests/cases/sync.sh`

**Interfaces:**
- Consumes: `python3 overlay/lib/sync.py catalog <endpoint>` из задачи 2.
- Produces: строки `SKIP <id>: нет в sync.conf` для паков каталога, не объявленных в составе.

- [ ] **Step 1: Написать падающие тесты**

Дописать в `overlay/tests/cases/sync.sh`:

```bash
test_sync_lists_undeclared_catalog_packs() {
  _write_sync_conf 'alpha'
  run_ok sync
  assert_contains "$SB/out.log" 'SKIP    beta: нет в sync.conf'
  assert_not_contains "$SB/out.log" 'SKIP    alpha:'
}

test_sync_declared_pack_missing_from_catalog() {
  _write_sync_conf 'nosuch'
  run_fail E_MCP sync
  assert_contains "$SB/out.log" 'Синк остановлен, ничего не записано'
}

test_sync_unreachable_server_writes_nothing() {
  _write_sync_conf 'alpha'
  export HARNESS_MCP_FIXTURE=""
  export HARNESS_MCP_URL="http://127.0.0.1:9/mcp"
  local before; before="$(tree_hash "$HARNESS_OVERLAY_SKILLS")"
  run_fail E_MCP sync apply
  assert_contains "$SB/out.log" 'Синк остановлен, ничего не записано'
  assert_eq "$(tree_hash "$HARNESS_OVERLAY_SKILLS")" "$before"
}

test_sync_does_not_touch_runtime_skills() {
  _write_sync_conf 'alpha'
  mkdir -p "$HOME/.claude/skills"
  local before; before="$(tree_hash "$HOME/.claude")"
  run_ok sync apply
  assert_eq "$(tree_hash "$HOME/.claude")" "$before"
}
```

Порт 9 — штатный discard, соединение на него отвергается сразу, поэтому тест не ждет таймаута.

- [ ] **Step 2: Запустить и убедиться, что падают**

Run: `bash overlay/tests/run.sh sync`
Expected: 18 тестов задач 1-4 и страховки от регрессии проходят, 3 новых падают. Под `set -e` сбой `sync_render` и так прерывает синк, а `sync.py` уже печатает `E_MCP` в лог, поэтому `test_sync_declared_pack_missing_from_catalog` и `test_sync_unreachable_server_writes_nothing` проверяют не сам код `E_MCP`, а строку «Синк остановлен, ничего не записано», которую печатает только новый код шага 3. `test_sync_does_not_touch_runtime_skills` проходит и до реализации — это страховка от регрессии, а не тест новой логики. Итог: `passed: 18, failed: 3`.

- [ ] **Step 3: Провести ошибку рендера наружу**

В `overlay/lib/sync.sh`, в `run_sync`, заменить строку

```bash
    hash="$(sync_render "$id")"
```

на

```bash
    hash="$(sync_render "$id")" ||
      die "E_MCP не удалось получить пак $id. Синк остановлен, ничего не записано."
```

`sync.py` уже напечатал подробность в stderr; здесь добавляется код и то, что делать.

- [ ] **Step 4: Печатать необъявленные паки каталога**

Дописать в `overlay/lib/sync.sh` перед `run_sync`:

```bash
# Паки каталога, которых нет в составе. Способ увидеть, что предлагает Киса.
sync_report_undeclared() {
  local declared="$1" catalog id
  catalog="$(python3 "$OVERLAY_DIR/lib/sync.py" catalog "$MCP_URL")" ||
    die "E_MCP не удалось получить каталог. Синк остановлен, ничего не записано."
  while read -r id; do
    [ -n "$id" ] || continue
    if ! grep -qx -- "$id" <<< "$declared"; then
      info "SKIP    $id: нет в $(basename "$SYNC_CONF")"
    fi
  done <<< "$catalog"
}
```

И в конце `run_sync`, перед блоком `if [ "$mode" = plan ]`, добавить:

```bash
  sync_report_undeclared "$(awk '{ print $2 }' <<< "$entries")"
```

- [ ] **Step 5: Дописать раздел в `README.md`**

В `overlay/README.md`, после раздела «Переезд своих скиллов» и перед разделом «Как это устроено», вставить:

````markdown
## Синк каталога deploychan

```bash
overlay/harness.sh sync         # показать, что приедет и что изменилось
overlay/harness.sh sync apply   # записать в overlay/skills/
```

Состав дистрибутива — в `overlay/sync.conf`: строка на пак, идентификатор из
каталога. Файл в git, поэтому на второй машине синк не нужен: скиллы приезжают
из репозитория обычным `apply`.

Синк — единственное, что ходит в сеть, и единственное, чему нужен `python3`.
`plan` и `apply` остаются оффлайновыми и без Python.

Правленный руками файл синк не перезаписывает: он показывает дифф и говорит
`edited`. Чтобы принять обновление, удалите каталог скилла и синкните заново.

**Дифф синканного `SKILL.md` смотрите как код.** Это инструкции, которым будет
следовать агент на всех ваших машинах, а не просто текст.
````

- [ ] **Step 6: Запустить и убедиться, что проходят**

Run: `bash overlay/tests/run.sh sync`
Expected: `passed: 21, failed: 0`.

- [ ] **Step 7: Запустить полный прогон**

Run: `bash overlay/tests/run.sh`
Expected: `passed: 120, failed: 0` (116 + 4).

- [ ] **Step 8: Commit**

```bash
git add overlay/lib/sync.sh overlay/README.md overlay/tests/cases/sync.sh
git commit -m "Добавлены необъявленные паки в выводе, остановка синка на сетевой ошибке и README" \
           -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Синк на настоящем каталоге

Задача не для субагента: она ходит в сеть и вносит в репозиторий содержимое, которое станет инструкциями для агента на всех машинах. Выполняет основной агент вместе с владельцем.

- [ ] **Step 1: Выбрать состав**

Run: `overlay/harness.sh sync`

С пустым `sync.conf` (кроме `x-content-advisor` из задачи 1) вывод покажет строки `SKIP` по остальным девяти пакам каталога. Показать владельцу список и вместе решить, что объявить.

- [ ] **Step 2: Посмотреть дифф каждого пака**

Run: `overlay/harness.sh sync`

Для каждого объявленного пака синк печатает `diff -u`. Прочитать их как код: это инструкции, которым будет следовать агент. Особое внимание — указаниям выполнять команды, обращаться к сети или трогать файлы вне репозитория.

- [ ] **Step 3: Записать — только после явного «ок» владельца**

Run: `overlay/harness.sh sync apply`

- [ ] **Step 4: Проверить дифф до коммита**

Run: `git status --short && git diff --stat`

Ни одного файла вне `overlay/skills/` и `overlay/sync.conf` быть не должно.

- [ ] **Step 5: Убедиться, что раскатка видит новые скиллы**

Run: `overlay/harness.sh plan`

Ожидается `new (overlay)` по каждому синканному паку для обоих рантаймов.

- [ ] **Step 6: Коммит содержимого**

Сообщение коммита называет, какие паки приехали.

---

## Проверка покрытия спека

| Требование спека | Задача |
|---|---|
| Команда `sync [plan|apply]`, не более двух аргументов | 1, тесты `test_sync_mode_accepted`, `test_sync_apply_submode_accepted`, `test_sync_rejects_extra_arg` |
| `overlay/sync.conf` в git, комментарии и пустые строки | 1, `test_sync_conf_parses_text_and_software` |
| Одно поле — текст, три — софт, иначе `E_PROFILE` с номером строки | 1, `test_sync_conf_bad_field_count` |
| Клиент к MCP на Python stdlib, только для синка | 2, `test_sync_py_catalog_from_fixture` |
| Фикстура вместо сети в тестах | 2, формат описан в Interfaces задачи 2 |
| Фронтматтер в конвенции апстрима | 3, `test_sync_materializes_text_pack` |
| `summary` и `reminder` в одну строку, кавычки экранированы | 3, `test_sync_normalizes_summary_and_skips_null_reminder` |
| `triggers` и `reminder` под `metadata.deploychan` | 3, `test_sync_puts_triggers_under_deploychan` |
| `reminder: null` и пустые `triggers` не дают пустых ключей | 3, `test_sync_normalizes_summary_and_skips_null_reminder` |
| Маркер `deploychan:<id> sha256:<хэш> <дата>` | 3, `test_sync_writes_origin_marker` |
| `plan` ничего не пишет | 3, `test_sync_plan_writes_nothing` |
| Состояния `same`, `updated`, `edited`, `foreign` | 4, четыре теста задачи 4 |
| Правленный файл не перезаписывается | 4, `test_sync_does_not_overwrite_edited_file` |
| Чужой скилл в слое не трогается | 4, `test_sync_does_not_touch_foreign_skill` |
| Паки каталога вне состава показаны как `SKIP` | 5, `test_sync_lists_undeclared_catalog_packs` |
| Объявленный пак вне каталога — `E_MCP` | 5, `test_sync_declared_pack_missing_from_catalog` |
| Недоступный сервер — `E_MCP`, ничего не записано | 5, `test_sync_unreachable_server_writes_nothing` |
| Синк не трогает каталоги рантаймов | 5, `test_sync_does_not_touch_runtime_skills` |
| Дисциплина ревью диффа | 5 (README), 6 (Step 2) |
| Синк на настоящем каталоге | 6 |

Вне этого плана остается софтовая ветка спека: клон объявленных репозиториев на закрепленную ревизию, предупреждение о локальных изменениях в клоне и печать команды установки. Она получает отдельный план поверх этого, потому что не использует MCP вовсе. В этом плане софтовые строки `sync.conf` разбираются и показываются, но не обрабатываются.

---

## DX-ревью 2026-09-24

`/plan-devex-review`, режим DX POLISH: скоуп спека не расширяется, каждое изменение сверх спека одобрено отдельным ответом владельца. Тип продукта: CLI для владельца харнеса. Ревью шло на плане после задачи 3; задачи 4-6 не реализованы.

### Персона

```
ЦЕЛЕВОЙ РАЗРАБОТЧИК
Кто:        владелец харнеса
Контекст:   возвращается к синку через несколько недель, когда Киса обновила каталог;
            харнес в целом знает, детали синка забыл
Терпимость: около 5 минут, дальше лезет в код
Ожидает:    безопасный запуск без аргументов, раздел в README, ошибки с подсказкой
```

### Путь глазами персоны

Подтвержден владельцем (D5). Метки: [код] взято из кода плана, [прогноз] догадка о реакции.

> Прошло пять недель, Киса обновила каталог. `overlay/harness.sh` без аргументов - это раскатка, не то. Нахожу в README раздел про синк и запускаю `overlay/harness.sh sync`. Вижу `SYNC x-content-advisor: updated`, под ним `diff -u`, потом `SKIP` по девяти пакам и "это был plan... Применить: sync apply" [код]. Хочу понять, что такое `telegram-custom-emoji-mosaic`, - в строке SKIP только идентификатор [код], иду спрашивать каталог в Claude [прогноз]. Делаю `sync apply`, вижу `WROTE`, открываю Claude - скилл старый. Минута недоумения, пока не вспоминаю: синк пишет в репозиторий, дальше `git diff`, коммит и `overlay/harness.sh apply` [прогноз; ни вывод, ни README этот шаг не называют - код]. Худший случай: объявил два пака, второй Киса переименовала. Синк записывает первый, падает на втором и пишет "ничего не записано", а `git status` показывает записанный первый [код: рендер и запись идут в одном цикле].

### Сравнение

Опубликованного времени онбординга ни у кого нет, поэтому сравниваются решения, а не минуты.

| Инструмент | От старта до результата | Время | Решение для сравнения | Источник |
|---|---|---|---|---|
| chezmoi | `chezmoi diff` -> `chezmoi apply`; на других машинах `chezmoi update` = pull + apply | не опубликовано | один шаг от "изменилось" до "работает"; дифф патчем | https://www.chezmoi.io/user-guide/daily-operations/ |
| Terraform | `plan` -> `apply`, в конце плана "Plan: 2 to add, 0 to change, 0 to destroy" | не опубликовано | итоговая строка со счетчиками | https://developer.hashicorp.com/terraform/tutorials/cli/plan |
| vendir | `vendir.yml` -> `vendir sync` -> lock с разрешенными ревизиями | не опубликовано | декларативный состав плюс lock | https://carvel.dev/vendir/docs/v0.25.0/sync/ |
| `sync` до ревью | README -> `sync` -> диффы; до "работает в Claude" еще `sync apply`, `git diff`, коммит, `harness.sh apply` | оценка: 2-5 мин до "понял", 6-10 мин до "работает" | состав в git, хэш-маркер, дифф в обоих режимах | план, задачи 1-5 |
| `sync` после ревью | то же, плюс итог, напоминание, описания в SKIP и подсказка следующего шага | оценка: 2-5 мин до "понял", 5-8 мин до "работает" | итоговая строка как у Terraform, честные ошибки | этот раздел |

Часы (D6): владелец через недели в терминале в репозитории -> понял, что изменилось в каталоге и какие инструкции получит агент. Цель Competitive, 2-5 минут. Чтение диффа намеренно медленное и не сокращается.

### Волшебный момент

Владелец одной командой видит, какие инструкции агент получит иначе, до того как они начнут действовать. Носитель (D7): диффы по пакам как в плане, плюс в самом конце вывода итоговая строка без токена, по образцу подсказки "это был plan":

```
[harness] итог: новых 1, обновлено 1, правлено руками 0, чужих 0, без изменений 3, не объявлено 9
```

### Карта пути

```
СТАДИЯ           | ВЛАДЕЛЕЦ ДЕЛАЕТ                 | ТРЕНИЕ                                 | СТАТУС
-----------------|---------------------------------|----------------------------------------|--------------------
1. Поиск         | --help, README                  | справка без пояснений (общая для       | вне объема
                 |                                 | всего харнеса)                         |
2. Установка     | ничего, нужен python3           | нет: E_PREREQ понятный                 | ok
3. Первый запуск | overlay/harness.sh sync         | SKIP без описаний                      | решено D9
4. Работа        | чтение диффов, sync apply       | нет итога, нет напоминания о ревью,    | решено D7, D11, D10
                 |                                 | нет следующего шага после apply        |
5. Отладка       | ошибки E_MCP, edited, foreign   | ложное "ничего не записано", неверная  | решено R1, R2, R3,
                 |                                 | причина, трейсбек, нет подсказки       | R5, R8
6. Обновление    | Киса меняет каталог, пак убран  | молчание про убранный пак              | решено D12
```

### Отчет "первый раз за недели"

```
T+0:00  Не помнит команду. --help -> usage со строкой sync [plan|apply] без пояснения.
        Идет в README -> "Синк каталога deploychan".                    [вне объема]
T+0:40  overlay/harness.sh sync. SYNC x-content-advisor: updated и дифф.
T+1:00  Строка SYNC zaebal: софт, ревизия v1.0 читается как "синкнуто",
        а софтовая ветка не реализована и пак пропущен.                 [решено R6]
T+2:30  Дочитал диффы; внизу итог, напоминание и SKIP с описаниями.     [решено D7, D11, D9]
T+3:30  sync apply -> WROTE и подсказка: git diff, коммит, harness apply. [решено D10]
T+5:00  Скилл работает в Claude.
```

### Журнал решений

| # | Источник | Было | Стало | Одобрение |
|---|---|---|---|---|
| D4 | шаг 0A | - | персона: владелец через недели | ответ владельца |
| D5 | шаг 0B | - | путь выше подтвержден | ответ владельца |
| D6 | шаг 0C | оценка 2-5 мин | цель Competitive 2-5 мин | ответ владельца |
| D7 | шаг 0D | диффы без итога | диффы плюс итоговая строка в конце | ответ владельца |
| D8 | шаг 0E | - | режим DX POLISH | ответ владельца |
| D9 | стадия 3 | `SKIP <id>: нет в sync.conf` | `SKIP <id>: нет в sync.conf — <summary до 80 символов>`; `sync.py catalog` печатает id, табуляцию и summary | ответ владельца |
| D10 | стадия 4 | после apply ничего | подсказка следующего шага в выводе и в README | ответ владельца |
| D11 | стадия 4 | правило только в README | строка под итогом, если есть new, updated или edited | ответ владельца |
| D12 | стадия 6 | убранный пак молча остается | WARN без удаления, в обоих режимах, строка в README | ответ владельца |
| D13 | проход 8 | цель не проверяется | `/devex-review` после реализации задач 1-5 | ответ владельца, не рекомендованный вариант |
| R1 | проход 3 | рендер и запись в одном цикле | две фазы: сначала каталог, проверка состава и рендер всех паков, потом запись | рутина: контракт спека "при любой E_MCP синк не пишет ничего" |
| R2 | проход 3 | все сбои `call()` подписаны "сервер недоступен" | сеть: "сервер <адрес> недоступен"; разбор: "ответ сервера <адрес> не разобран" | рутина: спек различает эти случаи E_MCP |
| R3 | проход 3 | edited: удалите и синкните заново | плюс "свою правку видно в git log -p overlay/skills/<id>/SKILL.md" | рутина: ошибка с подсказкой |
| R4 | проход 4 | README без витрины и состояний | README: SKIP показывает, что предлагает каталог; пять состояний | рутина: документация контракта спека |
| R5 | проход 3 | "не удалось получить пак" | "пака <id> нет в каталоге deploychan. Проверьте overlay/sync.conf: пак могли переименовать" | рутина: спек называет этот случай |
| R6 | шаг 0G | `SYNC <id>: софт, ревизия <rev>` | плюс "софтовая ветка не реализована, пропущен" | рутина: исправление вводящего в заблуждение статуса |
| R8 | проход 5 | KeyError в `render()` дает трейсбек | "E_MCP формат ответа каталога изменился: нет поля <имя>" | рутина: спек, риск 4 |

D1-D3 касались настроек gstack и классификации: коммиты остаются явными, корневой CLAUDE.md не создается, тип продукта CLI. На план они не влияют.

### Вне объема

- Пояснения команд в `--help`: справка общая для всего харнеса, POLISH ее не переделывает.
- Проверка заглушки Microsoft Store вместо `python3`: на машине владельца `python3` ведет на менеджер установки PSF и настоящий 3.14.5 (проверено 2026-09-24); на других машинах синк не запускают.
- Ссылки на документацию в текстах ошибок: отдельного сайта нет, документация - README.
- Телеметрия и автоматический замер времени: для личного инструмента неуместны; замер - через `/devex-review` (D13).
- Удаление паков, убранных из `sync.conf`: спек запрещает; D12 только предупреждает.

### Что уже есть и переиспользуется

- `info`, `warn`, `die` из `overlay/lib/common.sh` и формат `[harness] ТОКЕН    текст`.
- Подсказка "это был plan: ничего не записано. Применить: ..." из задачи 4 - образец для D10.
- `HARNESS_MCP_FIXTURE` и `overlay/tests/fixtures/catalog.json`: в `list_skills` у паков уже есть `summary`.
- `tree_hash`, `run_ok`, `run_fail`, `assert_*` в `overlay/tests/run.sh`.
- `E_PROFILE` с файлом и номером строки для `sync.conf` (задача 1).

### Оценки

```
+====================================================================+
|              DX PLAN REVIEW - SCORECARD                             |
+====================================================================+
| Измерение            | До     | После  |
|----------------------|--------|--------|
| Первый запуск        |  7/10  |  9/10  |
| CLI                  |  7/10  |  9/10  |
| Ошибки               |  5/10  |  8/10  |
| Документация         |  6/10  |  9/10  |
| Обновления           |  6/10  |  8/10  |
| Окружение            |  8/10  |  8/10  |
| Сообщество           |  7/10  |  7/10  |
| Измерение            |  2/10  |  6/10  |
+--------------------------------------------------------------------+
| До "понял"           | 2-5 мин (оценка), цель 2-5 мин              |
| До "работает"        | 6-10 мин -> 5-8 мин (оценка)                |
| Уровень              | Competitive                                 |
| Волшебный момент     | спроектирован: диффы плюс итоговая строка   |
| Тип продукта         | CLI для владельца                           |
| Режим                | DX POLISH                                   |
| Итого                |  6/10  |  8/10  |
+====================================================================+
| ПРИНЦИПЫ DX                                                         |
| Без трения на старте      | покрыто: sync без аргументов = plan    |
| Учиться делая             | покрыто: безопасный пробный запуск     |
| Бороться с неизвестностью | покрыто после D10, R1-R8               |
| Решать за меня + выход    | покрыто: plan по умолчанию, edited     |
| Код в контексте           | покрыто: настоящие диффы паков         |
| Волшебный момент          | покрыто: D7                            |
+====================================================================+
```

До реализации цель остается оценкой, а не замером.

### Чек-лист DX для реализации

```
[ ] До "понял" не дольше 5 минут - проверить через /devex-review (D13)
[ ] sync без аргументов безопасен и печатает осмысленный результат
[ ] Итоговая строка в конце вывода (D7)
[ ] Каждая ошибка: что случилось + почему + что делать + значения
[ ] При любой E_MCP в overlay/skills ничего не записано (R1)
[ ] README: команды, следующий шаг, витрина SKIP, пять состояний, убранные паки
[ ] Тест на каждое сообщение из этого раздела
```

### Задачи реализации

Выполняются отдельной задачей между задачей 5 и синком на настоящем каталоге. Перед выполнением задача расписывается кодом по правилам этого плана, с тестами и ожидаемыми числами. Тексты сообщений ниже точные.

- [ ] **T1 (P1, человек ~2 ч / CC ~20 мин)** - `sync.sh` - двухфазный `run_sync`
  - Источник: R1, R5. Фаза 1: каталог, проверка каждого объявленного текстового пака по каталогу (`E_MCP пака <id> нет в каталоге deploychan. Проверьте overlay/sync.conf: пак могли переименовать. Синк остановлен, ничего не записано.`), рендер всех паков и состояния. Фаза 2, только в apply: запись new и updated.
  - Файлы: `overlay/lib/sync.sh`, `overlay/tests/cases/sync.sh`
  - Проверка: тест "объявлены alpha и nosuch, sync apply -> E_MCP, alpha не записан".
- [ ] **T2 (P1, человек ~1 ч / CC ~10 мин)** - `sync.py` - честные причины E_MCP
  - Источник: R2, R8. Сеть: `сервер <адрес> недоступен: <текст>`. Разбор JSON: `ответ сервера <адрес> не разобран: <текст>`. Нет поля или не тот тип: `формат ответа каталога изменился: нет поля <имя>`, без трейсбека.
  - Файлы: `overlay/lib/sync.py`, `overlay/tests/cases/sync.sh`, фикстура для пака без поля
  - Проверка: тест на пак без поля `triggers` -> вывод содержит `формат ответа каталога изменился`, нет `Traceback`.
- [ ] **T3 (P2, человек ~30 мин / CC ~5 мин)** - `sync.py` и `sync.sh` - описания в SKIP
  - Источник: D9. `catalog` печатает id, табуляцию и `summary` одной строкой: переводы строк и табуляции заменены пробелами, обрезка до 80 символов. Строка: `SKIP    <id>: нет в sync.conf — <summary>`.
  - Файлы: `overlay/lib/sync.py`, `overlay/lib/sync.sh`, `overlay/tests/cases/sync.sh`
  - Проверка: `test_sync_py_catalog_from_fixture` переписывается под новый формат; тест SKIP проверяет описание беты.
- [ ] **T4 (P2, человек ~40 мин / CC ~5 мин)** - `sync.sh` - итог и напоминание
  - Источник: D7, D11. В конце: `итог: новых N, обновлено N, правлено руками N, чужих N, без изменений N, не объявлено N`. Под ним, если есть new, updated или edited: `Диффы выше - инструкции, которым будет следовать агент. Читайте их как код.`
  - Файлы: `overlay/lib/sync.sh`, `overlay/tests/cases/sync.sh`
  - Проверка: тест на счетчики; тест, что при всех same напоминания нет.
- [ ] **T5 (P2, человек ~20 мин / CC ~5 мин)** - `sync.sh`, README - следующий шаг после apply
  - Источник: D10. Если в apply что-то записано: `записано в overlay/skills. Дальше: git diff, коммит, overlay/harness.sh apply. До этого рантаймы новых скиллов не видят.`
  - Файлы: `overlay/lib/sync.sh`, `overlay/README.md`, `overlay/tests/cases/sync.sh`
  - Проверка: тест на строку после apply и ее отсутствие в plan.
- [ ] **T6 (P2, человек ~30 мин / CC ~5 мин)** - `sync.sh`, README - убранные паки
  - Источник: D12. Каталоги `overlay/skills/*` с маркером `deploychan:<id>`, которых нет в `sync.conf`: `WARN    <id> пришел из синка, но в sync.conf его нет. Удалите overlay/skills/<id>, если он больше не нужен.` Ничего не удаляется.
  - Файлы: `overlay/lib/sync.sh`, `overlay/README.md`, `overlay/tests/cases/sync.sh`
  - Проверка: тест "синкнуть alpha, убрать из sync.conf, sync -> WARN, каталог на месте".
- [ ] **T7 (P2, человек ~15 мин / CC ~3 мин)** - `sync.sh` - тексты edited и софта
  - Источник: R3, R6. edited: к предупреждению добавляется `Свою правку видно в git log -p overlay/skills/<id>/SKILL.md.` Софт: `SYNC    <id>: софт, ревизия <rev>: софтовая ветка не реализована, пропущен`.
  - Файлы: `overlay/lib/sync.sh`, `overlay/tests/cases/sync.sh`
  - Проверка: тесты ищут эти подстроки; тест задачи 1 продолжает проходить.
- [ ] **T8 (P2, человек ~15 мин / CC ~3 мин)** - README - витрина и состояния
  - Источник: R4. Фраза о том, что строки SKIP показывают остальные паки каталога, и список new, same, updated, edited, foreign с одной строкой смысла каждое.
  - Файлы: `overlay/README.md`
  - Проверка: чтение.
- [ ] **T9 (P3)** - `/devex-review` после реализации задач 1-5
  - Источник: D13. Не код: замер часов из D6 на живом инструменте.

### Нерешенные вопросы

Нет: все развилки этого ревью получили ответ владельца.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | - | - |
| Outside Review | codex, plan-review; замена - агент Plan в той же среде | Independent 2nd opinion | 1 | unavailable | нет: Codex не установлен, агент-замена не прислал отчет за 5 минут и остановлен |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 0 | - | - |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | - | - |
| DX Review | `/plan-devex-review` | Developer experience gaps | 1 | clean | score: 6/10 -> 8/10, TTHW: 2-5 мин -> 2-5 мин (оценка), 6 решений владельца, 7 рутинных правок |

**OUTSIDE COVERAGE:** codex, фаза plan-review, unavailable. Codex не установлен; агент Plan со свежим контекстом в той же среде запущен как замена, отчета за отведенные 5 минут не дал и остановлен, частичный результат не учитывался. Внешнего покрытия у этого ревью нет.

**VERDICT:** DX CLEAR (POLISH, 8/10, нерешенных развилок нет); eng review required.

NO UNRESOLVED DECISIONS
