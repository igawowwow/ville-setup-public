#!/usr/bin/env bash
# ==========================================================
#  ヴィレグループ Mac スタートキット
#  使い方（社員）:  curl -fsSL https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/install.sh | bash
#  使い方（手元）:  bash install.sh --profile dev
#
#  配布は公開の薄いリポ ville-setup-public から行う（DNS/本番サイトに触れない）。
#  中身の管理・開発はこのリポ（private）で行い、release.sh で public 側へ同期する。
# ==========================================================
set -uo pipefail

VG_REPO_RAW="${VG_REPO_RAW:-https://raw.githubusercontent.com/igawowwow/ville-setup-public/main}"
VG_HOME="${VG_HOME:-$HOME/.ville}"
PROFILE=""
DRY_RUN=0
MODE="install"

# ---------- 引数 ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --profile=*) PROFILE="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --update) MODE="update"; shift ;;
    --verify) MODE="verify"; shift ;;
    -h|--help)
      cat <<'EOS'
ヴィレグループ Mac スタートキット

  --profile <dev|sales|back-office>  役割を指定（未指定なら対話で聞く）
  --update                           既存環境を最新の共通設定に追いつかせる
  --verify                           入っているか確認するだけ（変更しない）
  --dry-run                          何をするか表示するだけ
EOS
      exit 0 ;;
    *) echo "不明なオプション: $1"; exit 1 ;;
  esac
done
export DRY_RUN

# ---------- ソース取得（curl|bash でもローカル実行でも動く） ----------
SELF_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n "$SELF_DIR" && -f "$SELF_DIR/lib/log.sh" ]]; then
  SRC="$SELF_DIR"
  # shellcheck source=lib/log.sh
  source "$SRC/lib/log.sh"
else
  # リモート実行: 必要ファイルを一時ディレクトリへ取得
  SRC="$(mktemp -d)"
  trap 'rm -rf "$SRC"' EXIT
  mkdir -p "$SRC"/{lib,brew,claude,dotfiles}
  for f in lib/log.sh verify.sh brew/Brewfile.core brew/Brewfile.dev brew/Brewfile.sales \
           brew/Brewfile.back-office claude/settings.template.json claude/CLAUDE.md \
           dotfiles/zshrc.ville; do
    curl -fsSL "$VG_REPO_RAW/$f" -o "$SRC/$f" || { echo "取得失敗: $f"; exit 1; }
  done
  source "$SRC/lib/log.sh"
fi

# ---------- ここから本体 ----------
printf "\n%s==============================================%s\n" "$C_B" "$C_RESET"
printf "%s  ヴィレグループ Mac スタートキット%s\n" "$C_B" "$C_RESET"
printf "%s==============================================%s\n" "$C_B" "$C_RESET"

[[ "$(uname -s)" == "Darwin" ]] || die "macOS 専用です（このMacは $(uname -s)）"
ARCH="$(uname -m)"
ok "macOS $(sw_vers -productVersion) / $ARCH"

if [[ "$MODE" == "verify" ]]; then
  bash "$SRC/verify.sh" 2>/dev/null || {
    step "確認"
    for c in brew git gh node claude; do
      command -v "$c" >/dev/null && ok "$c: $(command -v "$c")" || fail "$c: 未インストール"
    done
  }
  exit 0
fi

# ---------- プロファイル決定 ----------
step "役割（プロファイル）を決める"
VG_PROFILE_FILE="$VG_HOME/profile"
if [[ -z "$PROFILE" && -f "$VG_PROFILE_FILE" ]]; then
  PROFILE="$(cat "$VG_PROFILE_FILE")"
  ok "前回の設定を引き継ぎ: $PROFILE"
fi
if [[ -z "$PROFILE" ]]; then
  cat >/dev/tty <<'EOS'
   1) dev          … エンジニア / Claude Code で開発する人
   2) sales        … 営業（bizcore・HubSpot・Slack 中心）
   3) back-office  … 労務・経理・バックオフィス
EOS
  case "$(ask "番号を入力" "2")" in
    1) PROFILE="dev" ;;
    3) PROFILE="back-office" ;;
    *) PROFILE="sales" ;;
  esac
fi
[[ -f "$SRC/brew/Brewfile.$PROFILE" ]] || die "不明なプロファイル: $PROFILE"
ok "プロファイル: $PROFILE"
run mkdir -p "$VG_HOME"
[[ "$DRY_RUN" == "1" ]] || printf '%s\n' "$PROFILE" >"$VG_PROFILE_FILE"

# ---------- Xcode Command Line Tools ----------
step "開発ツール（Xcode CLT）"
if xcode-select -p >/dev/null 2>&1; then
  ok "既に導入済み"
else
  # GUIダイアログ（xcode-select --install）は「このソフトウェアは現在、
  # アップデートサーバから入手できないため、インストールできません」で
  # 詰まる環境が多いため、最初からそれには頼らない。
  # まず softwareupdate 経由の非対話インストールを裏で試す（数十秒〜数分）。
  warn "自動インストールを試す（パスワードは聞かれない、数十秒〜数分）"
  CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  run touch "$CLT_PLACEHOLDER"
  CLT_LABEL="$(softwareupdate -l 2>/dev/null | awk -F'Label: ' '/\* Label: .*Command Line Tools/{print $2}' | tail -n1)"
  if [[ -n "$CLT_LABEL" ]]; then
    run softwareupdate -i "$CLT_LABEL" --verbose
  fi
  run rm -f "$CLT_PLACEHOLDER"

  if xcode-select -p >/dev/null 2>&1; then
    ok "自動インストールできた"
  else
    fail "自動インストールが通らなかった（このMacはアップデートサーバ経由が塞がれている可能性が高い）"
    cat >&2 <<EOS

  手動ダウンロードに切り替える。ブラウザを開くので:
    1) Apple ID でサインイン（会社のでも個人のでもOK。持っていなければその場で無料作成できる）
    2) 一覧から「Command Line Tools for Xcode」を探す
       → お使いのmacOSは $(sw_vers -productVersion) なので、それに対応する最新のものを選ぶ
    3) ダウンロードした .dmg を開き、中の .pkg をダブルクリックしてインストーラーの指示に従う
    4) インストールが終わったらこのターミナルに戻り、もう一度この1行を実行:
         curl -fsSL https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/install.sh | bash

EOS
    run open "https://developer.apple.com/download/all/?q=Command+Line+Tools"
    [[ "$DRY_RUN" == "1" ]] || exit 0
  fi
fi

# ---------- Homebrew ----------
step "Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "$(brew --version | head -1)"
else
  warn "Homebrew を導入する（Macのパスワードを聞かれる）"
  # curl|bash 経由だとこのスクリプト自体が標準入力(パイプ)を使い切っていて、
  # Homebrewインストーラーがsudoパスワードを聞こうとしても「TTYじゃない」と
  # 判定されて失敗する。/dev/tty に繋ぎ直して本物のターミナル入力に戻す。
  if [[ -e /dev/tty ]]; then
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty \
      || die "Homebrew の導入に失敗"
  else
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew の導入に失敗"
  fi
fi
if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi

# ---------- パッケージ ----------
step "アプリ・コマンドを導入（数分〜十数分かかる）"
export HOMEBREW_NO_ENV_HINTS=1
if [[ "$DRY_RUN" == "1" ]]; then
  skip "brew bundle --file brew/Brewfile.core"
  skip "brew bundle --file brew/Brewfile.$PROFILE"
else
  brew bundle --file="$SRC/brew/Brewfile.core" || warn "core の一部が失敗（後で再実行すれば追いつく）"
  brew bundle --file="$SRC/brew/Brewfile.$PROFILE" || warn "$PROFILE の一部が失敗"
fi
ok "パッケージ処理完了"

# ---------- シェル設定 ----------
step "シェル設定（~/.zshrc）"
run mkdir -p "$VG_HOME"
run cp "$SRC/dotfiles/zshrc.ville" "$VG_HOME/zshrc.ville"
ensure_line "$HOME/.zshrc" '# --- ville-setup (自動追記。この行は消さない) ---'
ensure_line "$HOME/.zshrc" '[ -f "$HOME/.ville/zshrc.ville" ] && source "$HOME/.ville/zshrc.ville"'
ok "共通設定を読み込むようにした（個人の設定は ~/.zshrc にそのまま残る）"

# ---------- Git ----------
step "Git の名前とメール"
CUR_NAME="$(git config --global user.name 2>/dev/null || true)"
CUR_MAIL="$(git config --global user.email 2>/dev/null || true)"
if [[ -n "$CUR_NAME" && -n "$CUR_MAIL" ]]; then
  ok "設定済み: $CUR_NAME <$CUR_MAIL>"
else
  GN="$(ask "GitHubのユーザー名" "$CUR_NAME")"
  GM="$(ask "会社メールアドレス" "${CUR_MAIL:-@ville-ville.com}")"
  run git config --global user.name  "$GN"
  run git config --global user.email "$GM"
  ok "設定した: $GN <$GM>"
fi
run git config --global init.defaultBranch main
run git config --global pull.ff only
run git config --global push.autoSetupRemote true

# ---------- Claude Code ----------
step "Claude Code"
if command -v claude >/dev/null 2>&1; then
  ok "$(claude --version 2>/dev/null || echo '導入済み')"
else
  run bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || warn "Claude Code の導入に失敗。あとで手動で入れる"
fi

step "Claude Code の共通設定"
run mkdir -p "$HOME/.claude"
if [[ -f "$HOME/.claude/settings.json" ]]; then
  skip "既存の settings.json は触らない（上書きしない）"
else
  run cp "$SRC/claude/settings.template.json" "$HOME/.claude/settings.json"
  ok "settings.json を配置"
fi
# 全社ルールは常に最新へ更新（個人のメモは MEMORY.md 側なので消えない）
backup "$HOME/.claude/CLAUDE.md"
run cp "$SRC/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
ok "全社共通ルール（CLAUDE.md）を最新化"

# ---------- リポ置き場 ----------
step "作業フォルダ"
run mkdir -p "$HOME/repos"
ok "$HOME/repos を作成（vg コマンドで移動できる）"

# ---------- macOS の使いやすさ設定 ----------
step "macOS の初期設定を業務向けに調整"
run defaults write NSGlobalDomain KeyRepeat -int 2
run defaults write NSGlobalDomain InitialKeyRepeat -int 15
run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
run defaults write com.apple.finder AppleShowAllExtensions -bool true   # 拡張子を常に表示
run defaults write com.apple.finder ShowPathbar -bool true
run defaults write com.apple.screencapture location -string "$HOME/Downloads"
run mkdir -p "$HOME/Downloads"
run killall Finder 2>/dev/null || true
ok "キーリピート高速化・拡張子表示・スクショは Downloads へ"

# ---------- 認証（本人の操作が必要。ターミナルを開き直した瞬間に自動で誘導する） ----------
step "ログイン（次にターミナルを開いたときに自動で1つずつ案内される）"
# macOS 標準の bash 3.2 では空配列 + set -u が事故るので改行区切りの文字列で持つ
NEED_AUTH=""
PENDING_CMDS=""
add_auth() { NEED_AUTH="${NEED_AUTH}$1"$'\n'; PENDING_CMDS="${PENDING_CMDS}$2"$'\n'; }
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ok "GitHub: ログイン済み"
  else add_auth "gh auth login          # GitHub（ブラウザが開く）" "gh auth login --hostname github.com --git-protocol https --web"; fi
fi
if command -v claude >/dev/null 2>&1; then
  add_auth "claude                  # 初回起動でログイン案内が出る" "claude"
fi
if [[ "$PROFILE" == "dev" ]] && command -v gcloud >/dev/null 2>&1; then
  if gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q .; then
    ok "Google Cloud: ログイン済み"
  else
    add_auth "gcloud auth login       # Google Cloud" "gcloud auth login"
    add_auth "gcloud auth application-default login" "gcloud auth application-default login"
  fi
fi

if [[ -n "$PENDING_CMDS" && "$DRY_RUN" != "1" ]]; then
  run mkdir -p "$VG_HOME"
  printf '%s' "$PENDING_CMDS" >"$VG_HOME/pending-auth"
  ok "ターミナルを開き直すと自動で1つずつ実行される（ブラウザでの確認だけ本人が行う）"
fi

# ---------- 完了 ----------
printf "\n%s==============================================%s\n" "$C_G" "$C_RESET"
printf "%s  セットアップ完了%s\n" "$C_G$C_B" "$C_RESET"
printf "%s==============================================%s\n" "$C_G" "$C_RESET"
echo
echo "  ▸ ターミナルを一度閉じて開き直す（設定を読み込むため）"
if [[ -n "$NEED_AUTH" ]]; then
  echo "  ▸ 開き直すと、下のログインが自動で1つずつ案内される（ブラウザの確認だけやればいい）:"
  printf '%s' "$NEED_AUTH" | while IFS= read -r a; do echo "      $a"; done
fi
cat <<'EOS'
  ▸ Slack と Google Drive はアプリを起動して会社アカウントでログイン
  ▸ 1Password の招待メールから会社アカウントに参加（パスワードは全部ここ）

  環境が壊れた / 設定を最新にしたい:   vg-update
  何が入っているか確認:                bash <(curl -fsSL https://ville-ville.com/setup) --verify
EOS
echo
