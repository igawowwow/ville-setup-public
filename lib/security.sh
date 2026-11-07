#!/usr/bin/env bash
# リモートワーク用のセキュリティ一式（install.sh から source する）
#   sec_harden … 設定を入れる（何度流しても同じ結果になる）
#   sec_check  … 確認だけ（何も変えない。verify.sh から呼ぶ）
# 前提: lib/log.sh を source 済み

VG_LOST_TEXT="${VG_LOST_TEXT:-ヴィレグループの業務用PCです。拾われた方は 050-1720-8945 までご連絡ください。}"
VILLESEE_BASE="https://zxstlygsulxsdpehvsua.supabase.co/storage/v1/object/public/agent"

_sudo() { # curl|bash でもパスワードを聞けるように端末へ繋ぐ
  if [[ "${DRY_RUN:-0}" == "1" ]]; then printf "  %s(dry-run)%s sudo %s\n" "$C_Y" "$C_RESET" "$*" >&2; return 0; fi
  if [[ -e /dev/tty ]]; then sudo "$@" </dev/tty; else sudo "$@"; fi
}

_villesee_app() {
  local d
  for d in "$HOME/Applications" "/Applications"; do
    [[ -d "$d/Villsee Agent.app" ]] && { echo "$d/Villsee Agent.app"; return 0; }
  done
  return 1
}

sec_harden() {
  step "セキュリティ設定（Macのパスワードを聞かれる）"
  [[ "${DRY_RUN:-0}" == "1" ]] || _sudo -v || { warn "管理者パスワードが通らなかったのでセキュリティ設定を飛ばした（vg-update でやり直せる）"; return 0; }

  # ディスク暗号化: PCを無くしても中身を読まれない
  if fdesetup isactive >/dev/null 2>&1; then
    ok "ディスク暗号化（FileVault）: オン"
  else
    warn "ディスク暗号化（FileVault）がオフ → 設定画面を開くので「オンにする」を押す"
    warn "  復旧方法は「iCloudアカウント」を選ぶ（復旧キーを選んだら紙に書いて保管。Slack・メモ帳に書かない）"
    run open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault" 2>/dev/null \
      || run open "x-apple.systempreferences:com.apple.preference.security?FDE" 2>/dev/null || true
  fi

  # ファイアウォール: 外から勝手に繋がれない＋存在を隠す
  local fw=/usr/libexec/ApplicationFirewall/socketfilterfw
  _sudo "$fw" --setglobalstate on >/dev/null && _sudo "$fw" --setstealthmode on >/dev/null \
    && ok "ファイアウォール: オン（ステルス）" || warn "ファイアウォールの設定に失敗"

  # macOS・アプリの更新を自動で入れる（穴が開いたまま放置しない）
  local su=/Library/Preferences/com.apple.SoftwareUpdate
  _sudo defaults write "$su" AutomaticCheckEnabled -bool true
  _sudo defaults write "$su" AutomaticDownload -bool true
  _sudo defaults write "$su" AutomaticallyInstallMacOSUpdates -bool true
  _sudo defaults write "$su" CriticalUpdateInstall -bool true
  _sudo defaults write "$su" ConfigDataInstall -bool true
  _sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true
  ok "macOS・App Store の自動アップデート: オン"

  # 席を離れたら自動でロック（5分でスクリーンセーバー→すぐパスワード）
  run defaults -currentHost write com.apple.screensaver idleTime -int 300
  _sudo pmset -a displaysleep 10 >/dev/null
  if sysadminctl -screenLock status 2>&1 | grep -q immediate; then
    ok "画面ロック: 5分で自動ロック・解除にパスワード"
  else
    warn "画面ロックを「すぐにパスワード」にする（もう一度Macのパスワードを聞かれる）"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then skip "sysadminctl -screenLock immediate"
    elif sysadminctl -screenLock immediate -password - </dev/tty 2>/dev/null; then ok "画面ロック: 5分で自動ロック・解除にパスワード"
    else warn "画面ロックの設定に失敗 → システム設定 > ロック画面 で「すぐに」を選ぶ"; fi
  fi

  # ゲストユーザーを無効（誰でもログインできる入口を塞ぐ）
  _sudo sysadminctl -guestAccount off >/dev/null 2>&1
  _sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
  ok "ゲストユーザー: オフ"

  # AirDrop は連絡先のみ（カフェ・電車で知らない人からファイルを受けない）
  run defaults write com.apple.sharingd DiscoverableMode -string "Contacts Only"
  ok "AirDrop: 連絡先のみ"

  # 無くしたとき用: ログイン画面に連絡先
  _sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "$VG_LOST_TEXT"
  ok "ログイン画面に落とし物の連絡先を表示"

  # 外から入れる共有機能は、オンになっていれば知らせる（業務で使っている人もいるので勝手に切らない）
  local listen svc
  listen="$(netstat -anp tcp 2>/dev/null | awk '/LISTEN/{print $4}')"
  for svc in "5900:画面共有" "445:ファイル共有" "22:リモートログイン(SSH)"; do
    printf '%s\n' "$listen" | grep -qE "\.${svc%%:*}\$" \
      && warn "${svc#*:} がオン → 使っていなければ システム設定 > 一般 > 共有 でオフに"
  done

  # 偽アプリを止める仕組み（Gatekeeper / SIP）はオンのままか確認だけ
  spctl --status 2>/dev/null | grep -q enabled && ok "Gatekeeper: オン" || warn "Gatekeeper がオフ → 管理者に連絡"
  csrutil status 2>/dev/null | grep -q enabled && ok "システム保護（SIP）: オン" || warn "SIP がオフ → 管理者に連絡"

  villesee_install
}

villesee_install() {
  step "Villesee（勤怠の見える化アプリ）"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then skip "Villesee Agent を最新版で導入"; return 0; fi
  local plat m url sha t dest app
  case "$(uname -m)" in arm64) plat=macos-aarch64 ;; *) plat=macos-x86_64 ;; esac
  m="$(curl -fsSL "$VILLESEE_BASE/latest.json")" || { warn "Villesee の配布先に繋がらない（vg-update でやり直せる）"; return 0; }
  url="$(printf '%s' "$m" | /usr/bin/python3 -c "import json,sys;print(json.load(sys.stdin)['platforms']['$plat']['url'])" 2>/dev/null)"
  sha="$(printf '%s' "$m" | /usr/bin/python3 -c "import json,sys;print(json.load(sys.stdin)['platforms']['$plat']['sha256'])" 2>/dev/null)"
  [[ -n "$url" && -n "$sha" ]] || { warn "Villesee: このMac向けの版が見つからない"; return 0; }
  t="$(mktemp -d)"
  if ! curl -fsSL "$url" -o "$t/a.tgz" || [[ "$(shasum -a 256 "$t/a.tgz" | cut -d' ' -f1)" != "$sha" ]]; then
    rm -rf "$t"; warn "Villesee のダウンロードが壊れていた（vg-update でやり直せる）"; return 0
  fi
  tar -xzf "$t/a.tgz" -C "$t"
  # 前の版の場所に入れる（自動起動の登録がその場所を指しているため）
  if app="$(_villesee_app)"; then dest="$(dirname "$app")"; else dest="$HOME/Applications"; fi
  mkdir -p "$dest"
  pkill -f "Villsee Agent.app/Contents/MacOS/" 2>/dev/null || true
  sleep 1
  rm -rf "$dest/Villsee Agent.app"
  mv "$t/Villsee Agent.app" "$dest/"
  xattr -dr com.apple.quarantine "$dest/Villsee Agent.app" 2>/dev/null || true
  rm -rf "$t"
  open "$dest/Villsee Agent.app"
  ok "Villesee を導入・起動（以後は自動で最新になる）"
  warn "「画面収録」の許可を聞かれたら「許可」を押す（最初の1回だけ）"
}

# ---------- 確認だけ（変更しない） ----------
sec_check() { # NG の数を返り値にせず、グローバル NG に足す
  step "セキュリティ"
  fdesetup isactive >/dev/null 2>&1 && ok "ディスク暗号化（FileVault）" \
    || { fail "ディスク暗号化がオフ → システム設定 > プライバシーとセキュリティ > FileVault"; NG=$((NG+1)); }
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -qi "enabled\|有効" \
    && ok "ファイアウォール" || { fail "ファイアウォールがオフ → vg-update"; NG=$((NG+1)); }
  [[ "$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null)" == "1" ]] \
    && ok "自動アップデート" || { fail "自動アップデートがオフ → vg-update"; NG=$((NG+1)); }
  sysadminctl -screenLock status 2>&1 | grep -q immediate \
    && ok "画面ロック（すぐにパスワード）" || { fail "画面ロックが「すぐに」ではない → システム設定 > ロック画面"; NG=$((NG+1)); }
  [[ "$(defaults read /Library/Preferences/com.apple.loginwindow GuestEnabled 2>/dev/null)" == "0" ]] \
    && ok "ゲストユーザー無効" || { fail "ゲストユーザーが有効 → vg-update"; NG=$((NG+1)); }
  spctl --status 2>/dev/null | grep -q enabled && ok "Gatekeeper" || { fail "Gatekeeper がオフ"; NG=$((NG+1)); }
  csrutil status 2>/dev/null | grep -q enabled && ok "システム保護（SIP）" || { fail "SIP がオフ"; NG=$((NG+1)); }

  if command -v warp-cli >/dev/null 2>&1; then
    warp-cli --accept-tos status 2>/dev/null | grep -qi connected \
      && ok "会社VPN（WARP）: 接続中" || { fail "会社VPN（WARP）が未接続 → WARPアプリで会社メールにログイン"; NG=$((NG+1)); }
  else
    fail "会社VPN（WARP）が入っていない → vg-update"; NG=$((NG+1))
  fi

  if _villesee_app >/dev/null; then
    pgrep -f "Villsee Agent.app/Contents/MacOS/" >/dev/null && ok "Villesee: 起動中" \
      || { fail "Villesee が止まっている → アプリを開く"; NG=$((NG+1)); }
  else
    fail "Villesee が入っていない → vg-update"; NG=$((NG+1))
  fi
}
