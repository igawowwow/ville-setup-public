#!/usr/bin/env bash
# 共通ユーティリティ（install.sh / verify.sh から source する）

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_B=$'\033[1m'
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_C=$'\033[36m'
else
  C_RESET=""; C_B=""; C_G=""; C_Y=""; C_R=""; C_C=""
fi

STEP_NO=0
step()  { STEP_NO=$((STEP_NO+1)); printf "\n%s[%d]%s %s%s%s\n" "$C_C" "$STEP_NO" "$C_RESET" "$C_B" "$*" "$C_RESET"; }
ok()    { printf "  %s✓%s %s\n" "$C_G" "$C_RESET" "$*"; }
skip()  { printf "  %s-%s %s\n" "$C_Y" "$C_RESET" "$*"; }
warn()  { printf "  %s!%s %s\n" "$C_Y" "$C_RESET" "$*"; }
fail()  { printf "  %s×%s %s\n" "$C_R" "$C_RESET" "$*"; }
die()   { fail "$*"; exit 1; }

# curl | bash でも対話できるように必ず /dev/tty から読む
ask() { # ask "質問" "デフォルト" -> 標準出力に答え
  local q="$1" def="${2:-}" ans=""
  if [[ ! -t 0 && ! -e /dev/tty ]]; then echo "$def"; return; fi
  if [[ -n "$def" ]]; then
    printf "  %s? %s [%s]: %s" "$C_C" "$q" "$def" "$C_RESET" >/dev/tty
  else
    printf "  %s? %s: %s" "$C_C" "$q" "$C_RESET" >/dev/tty
  fi
  read -r ans </dev/tty || true
  echo "${ans:-$def}"
}

confirm() { # confirm "やる？" -> 0/1
  local a; a="$(ask "$1 (y/N)" "N")"
  [[ "$a" =~ ^[yY] ]]
}

run() { # DRY_RUN 対応の実行
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf "  %s(dry-run)%s %s\n" "$C_Y" "$C_RESET" "$*"
  else
    "$@"
  fi
}

# ファイルに1行を冪等追記
ensure_line() { # ensure_line <file> <line>
  local f="$1" line="$2"
  [[ -f "$f" ]] || run touch "$f"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf "  %s(dry-run)%s append to %s: %s\n" "$C_Y" "$C_RESET" "$f" "$line"; return
  fi
  grep -qxF "$line" "$f" 2>/dev/null || printf '%s\n' "$line" >>"$f"
}

# 既存ファイルを壊さないバックアップ
backup() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local b="${f}.ville-bak.$(date +%Y%m%d%H%M%S)"
  run cp -a "$f" "$b" && ok "バックアップ: $b"
}
