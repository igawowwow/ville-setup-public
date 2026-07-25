#!/usr/bin/env bash
# 導入後のセルフチェック（何も変更しない）
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SELF_DIR/lib/log.sh" ]]; then source "$SELF_DIR/lib/log.sh"
else
  ok(){ echo "  ✓ $*"; }; fail(){ echo "  × $*"; }; warn(){ echo "  ! $*"; }
  step(){ echo; echo "[$*]"; }
fi

NG=0
check_cmd() { # check_cmd <コマンド> <説明>
  if command -v "$1" >/dev/null 2>&1; then ok "$2（$1）"
  else fail "$2 が入っていない → vg-update で再実行"; NG=$((NG+1)); fi
}
check_app() {
  if [[ -d "/Applications/$1.app" ]]; then ok "$1"
  else warn "$1 が見つからない"; fi
}

step "コマンド"
check_cmd brew "Homebrew"
check_cmd git  "Git"
check_cmd gh   "GitHub CLI"
check_cmd claude "Claude Code"
check_cmd jq   "jq"
check_cmd rg   "ripgrep"

step "アプリ"
check_app "Google Chrome"
check_app "Slack"
check_app "Google Drive"

step "設定ファイル"
[[ -f "$HOME/.ville/zshrc.ville" ]] && ok "共通シェル設定" || { fail "共通シェル設定なし"; NG=$((NG+1)); }
grep -q 'ville/zshrc.ville' "$HOME/.zshrc" 2>/dev/null && ok "~/.zshrc から読み込み済み" || { fail "~/.zshrc に読み込み行がない"; NG=$((NG+1)); }
[[ -f "$HOME/.claude/CLAUDE.md" ]] && ok "全社共通ルール" || warn "全社共通ルールなし"
[[ -f "$HOME/.claude/settings.json" ]] && ok "Claude Code 設定" || warn "Claude Code 設定なし"

step "ログイン状態"
git config --global user.email >/dev/null 2>&1 && ok "Git: $(git config --global user.email)" || { fail "Git のメール未設定"; NG=$((NG+1)); }
if command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 && ok "GitHub ログイン済み" || warn "GitHub 未ログイン → gh auth login"
fi
if command -v gcloud >/dev/null 2>&1; then
  gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q . \
    && ok "Google Cloud ログイン済み" || warn "Google Cloud 未ログイン → gcloud auth login"
fi

step "マシンの健康状態"
# 実データは /System/Volumes/Data 側にある。/ は読み取り専用なので見ても意味がない
AVAIL_PCT=$(df -P "$HOME" | awk 'NR==2{gsub("%","",$5); print 100-$5}')
AVAIL_GB=$(df -Pg "$HOME" | awk 'NR==2{print $4}')
if [[ "$AVAIL_PCT" -lt 10 ]]; then
  fail "ディスク空きが ${AVAIL_PCT}%（${AVAIL_GB}GB）— 10%未満はMacが重くなる。不要ファイルを消すこと"
  NG=$((NG+1))
else
  ok "ディスク空き ${AVAIL_PCT}%（${AVAIL_GB}GB）"
fi
LOAD=$(sysctl -n vm.loadavg | awk '{print $2}')
CORES=$(sysctl -n hw.ncpu)
ok "負荷 ${LOAD} / ${CORES}コア"
SWAP=$(sysctl -n vm.swapusage | awk '{print $6}')
ok "スワップ使用 ${SWAP}"

echo
if [[ "$NG" -eq 0 ]]; then
  echo "  結果: 問題なし ✅"
else
  echo "  結果: ${NG}件の問題あり。vg-update を実行、直らなければSlackで管理者へ"
  exit 1
fi
