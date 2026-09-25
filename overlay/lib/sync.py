#!/usr/bin/env python3
"""Клиент к MCP deploychan. Вызывается только режимом sync.

Сервер stateless: tools/call работает без initialize, сессия не нужна.
Формы ответа у инструментов разные, поэтому обе обрабатываются здесь,
а bash про JSON ничего не знает.
"""
import hashlib
import http.client
import json
import os
import sys
import unicodedata
import urllib.request

TIMEOUT = 30
SUMMARY_LIMIT = 80
# Перед сервером стоит Cloudflare: на стандартный User-Agent Python он отвечает
# 403 с "error code: 1010" (проверено 2026-09-25). Клиент называет себя сам.
USER_AGENT = "kisa-harness-sync/1.0"
# U+202A..U+202E (LRE, RLE, PDF, LRO, RLO) и U+2066..U+2069 (LRI, RLI, FSI, PDI):
# переставляют направление текста, дифф показывает не то, что прочтет агент.
BIDI_CONTROLS = frozenset(range(0x202A, 0x202F)) | frozenset(range(0x2066, 0x206A))


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


def _unwrap(result):
    if result.get("isError"):
        texts = [item.get("text", "") for item in result.get("content") or []]
        raise McpError(" ".join(texts).strip() or "инструмент вернул ошибку")
    if "structuredContent" in result:
        return result["structuredContent"]["result"]
    content = result.get("content") or []
    if not content:
        raise McpError("пустой ответ инструмента")
    return json.loads(content[0]["text"])


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
    try:
        request = urllib.request.Request(
            endpoint,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json, text/event-stream",
                "User-Agent": USER_AGENT,
            },
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            raw = response.read()
    except (OSError, ValueError, http.client.HTTPException) as exc:
        raise McpError("сервер %s недоступен: %s" % (endpoint, exc))
    try:
        body = json.loads(raw.decode("utf-8"))
        result = body.get("result")
        if result is None:
            raise McpError("ответ сервера %s не разобран: нет result" % endpoint)
        return _unwrap(result)
    except (AttributeError, IndexError, KeyError, TypeError, ValueError) as exc:
        raise McpError("ответ сервера %s не разобран: %s" % (endpoint, exc))


def one_line(value):
    return " ".join((value or "").split())


def yaml_string(value):
    text = one_line(value).replace("\\", "\\\\").replace('"', '\\"')
    return '"%s"' % text


def yaml_list(values):
    return "[%s]" % ", ".join(yaml_string(item) for item in values or [])


def _format_error(detail):
    return McpError("формат ответа каталога изменился: %s" % detail)


def _reject_bad_chars(value, ident, field):
    """Управляющие и bidi-символы прячут текст от того, кто читает diff -u.
    Отклоняем: категорию Unicode Cc (кроме \\t и \\n) и bidi-переключатели
    направления письма. Одиночный \\r тоже Cc и тоже отклоняется - в терминале
    он возвращает курсор и затирает строку."""
    if value is None:
        return
    text = value.replace("\r\n", "\n")
    for ch in text:
        if ch in ("\t", "\n"):
            continue
        cp = ord(ch)
        if unicodedata.category(ch) == "Cc" or cp in BIDI_CONTROLS:
            raise McpError(
                "пак %s отклонен: в поле %s управляющий символ U+%04X. "
                "В диффе такой текст выглядит не так, как его прочтет агент."
                % (ident, field, cp)
            )


def check_pack(pack, skill_id):
    """Форма пака, сверенная по живому каталогу. Лучше E_MCP, чем мусор в SKILL.md."""
    if not isinstance(pack, dict):
        raise _format_error("пак %s пришел не объектом" % skill_id)
    if pack.get("id") != skill_id:
        raise _format_error("у пака %s нет поля id или оно другое" % skill_id)
    _reject_bad_chars(pack.get("id"), skill_id, "id")
    if not isinstance(pack.get("body"), str):
        raise _format_error("у пака %s нет поля body" % skill_id)
    _reject_bad_chars(pack.get("body"), skill_id, "body")
    for name in ("summary", "reminder"):
        value = pack.get(name)
        if value is not None and not isinstance(value, str):
            raise _format_error("у пака %s поле %s не строка" % (skill_id, name))
        _reject_bad_chars(value, skill_id, name)
    for name in ("tags", "triggers"):
        value = pack.get(name)
        if value is not None and not (
            isinstance(value, list) and all(isinstance(item, str) for item in value)
        ):
            raise _format_error("у пака %s поле %s не список строк" % (skill_id, name))
        for item in value or []:
            _reject_bad_chars(item, skill_id, name)


def check_catalog(items):
    if not isinstance(items, list):
        raise _format_error("list_skills вернул не список")
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise _format_error("в list_skills пак без поля id")
        item_id = item["id"]
        _reject_bad_chars(item_id, repr(item_id), "id")
        summary = item.get("summary")
        if summary is not None and not isinstance(summary, str):
            raise _format_error("у пака %s поле summary не строка" % item_id)
        _reject_bad_chars(summary, item_id, "summary")


def short_summary(value):
    text = one_line(value)
    if len(text) > SUMMARY_LIMIT:
        text = text[: SUMMARY_LIMIT - 3].rstrip() + "..."
    return text


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
    items = call(endpoint, "list_skills", {})
    check_catalog(items)
    for item in items:
        print("%s\t%s" % (item["id"], short_summary(item.get("summary"))))


def cmd_hash(path):
    with open(path, "rb") as handle:
        data = handle.read()
    print(hashlib.sha256(data).hexdigest())


def cmd_render(endpoint, skill_id, outdir):
    pack = call(endpoint, "get_skill", {"skill_id": skill_id})
    check_pack(pack, skill_id)
    text = render(pack)
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, "SKILL.md")
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(hashlib.sha256(text.encode("utf-8")).hexdigest())


def main(argv):
    # На Windows вывод Python в конвейер идет в кодировке системы (cp1251) и с
    # \r\n. Bash читает UTF-8 и сравнивает побайтово, поэтому здесь принудительно
    # UTF-8 и LF (как и при записи SKILL.md в cmd_render выше).
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")
    sys.stderr.reconfigure(encoding="utf-8", newline="\n")
    if len(argv) >= 2 and argv[1] == "hash":
        if len(argv) != 3:
            sys.stderr.write("usage: sync.py hash <файл>\n")
            return 2
        cmd_hash(argv[2])
        return 0
    if len(argv) < 3:
        sys.stderr.write("usage: sync.py <catalog|render|hash> <endpoint> [id outdir]\n")
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
