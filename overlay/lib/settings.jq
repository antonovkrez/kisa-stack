# Слияние хуков харнеса в settings.json Claude Code.
# Вход: текущий settings.json (или {}).
# Аргументы: $ex (slurpfile settings.hooks.example.json апстрима), $wiki,
#            $anchor, $reminder (строки command), $automem_off ("0"|"1").

# Хук "наш", если у него command - строка с именем нашего скрипта. У чужого
# хука command может быть числом, объектом или отсутствовать вовсе - это не
# наш хук, но и не повод падать.
def is_ours($script):
  (.command // null) as $c | if ($c | type) == "string" then ($c | contains($script)) else false end;

# Если на событии уже есть хук с этим скриптом - обновить его command,
# иначе добавить запись апстрима. Чужие записи (в том числе с "hooks" не
# массивом) не трогаются и не роняют слияние.
def upsert($entry; $script):
  if any(.[]?; any(.hooks[]?; is_ours($script)))
  then map(if (has("hooks") and (.hooks | type) == "array")
           then .hooks |= map(if is_ours($script)
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
