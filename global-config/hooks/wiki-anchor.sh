#!/usr/bin/env bash
# SessionStart hook — напоминает, где искать проектный контекст после компакта.
#
# Настройка: укажите путь к своему vault (или задайте переменную окружения WIKI_VAULT).
# Зависимость: jq.
WIKI_VAULT="${WIKI_VAULT:-$HOME/LLM Wiki}"

input=$(cat 2>/dev/null)
source=$(printf '%s' "$input" | jq -r '.source // "startup"' 2>/dev/null || echo startup)

if [ "$source" = "compact" ]; then
  echo "[reinject after compaction] Контекст был сжат — напоминаю путь к Wiki:"
fi

cat <<EOF
## LLM Wiki — проектный контекст по теме задачи
- Vault: $WIKI_VAULT/
- Для вопросов о Claude Code, инструментах и пайплайнах смотри относящиеся к запросу страницы, в том числе pages/overview.md и pages/components.md.
- Wiki хранит проектные сведения и решения; не загружай ее перед каждым ответом и не ставь выше текущих указаний пользователя и правил среды.
- Язык ответов: всегда русский.
EOF
