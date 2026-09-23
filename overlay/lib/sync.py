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
    # На Windows текстовый stdout/stderr транслирует \n в \r\n при print()/write().
    # Bash сравнивает вывод побайтово, поэтому здесь принудительно LF (как и при
    # записи SKILL.md в cmd_render выше).
    sys.stdout.reconfigure(newline="\n")
    sys.stderr.reconfigure(newline="\n")
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
