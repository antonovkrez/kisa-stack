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
