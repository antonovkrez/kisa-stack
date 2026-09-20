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
