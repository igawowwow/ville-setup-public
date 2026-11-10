#!/bin/bash
# 会社VPN（WARP）を1行で入れる。
#   curl -fsSL https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/warp.sh | bash
# やること: 公式インストーラーを入れる → チーム villegroup を最初から指す設定を置く → アプリを開く。
# 社員がやるのは Mac のパスワード1回と、会社メール → 6桁のコードだけ。
# 入れ済みのMacで流すと、設定（OFFにしても3分で自動でONに戻る など）を新しくするだけで終わる。
set -euo pipefail

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }

if [[ "$(uname)" != "Darwin" ]]; then
  echo "このコマンドは Mac 用です。Windows はマニュアルの Windows の手順へ。"; exit 1
fi

W="/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli"

# チーム名・使い方の選択画面を出さずに、会社のログインへ直行させる設定
# auto_connect=3: スイッチをOFFにしても3分で自動でONに戻る（戻し忘れ防止）
write_mdm() {
  sudo mkdir -p "/Library/Application Support/Cloudflare"
  sudo tee "/Library/Application Support/Cloudflare/mdm.xml" >/dev/null <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>organization</key><string>villegroup</string>
  <key>auto_connect</key><integer>3</integer>
  <key>service_mode</key><string>warp</string>
  <key>onboarding</key><false/>
</dict>
</plist>
XML
}

gateway_on() { curl -s https://cloudflare.com/cdn-cgi/trace | grep -q "gateway=on"; }

say "① 会社VPN（WARP）を設定します。途中で Mac のパスワードを聞かれたら入力して Enter（文字は表示されません）"
sudo -v </dev/tty

# すでに会社のWARPに入っているMacは、設定を新しくするだけ
if [[ -x "$W" ]] && "$W" registration show 2>/dev/null | grep -q "Organization: villegroup"; then
  write_mdm
  "$W" mdm refresh >/dev/null 2>&1 \
    || sudo launchctl kickstart -k system/com.cloudflare.1dot1dot1dot1.macos.warp.daemon || true
  "$W" connect >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do gateway_on && break; sleep 2; done
  say "✅ 設定を新しくしました。開けないサイトでOFFにしても、3分で自動でONに戻ります。"
  exit 0
fi

PKG="$(mktemp -d)/Cloudflare_WARP.pkg"
curl -fsSL -o "$PKG" https://downloads.cloudflareclient.com/v1/download/macos/ga
pkgutil --check-signature "$PKG" | grep -q "Developer ID Installer: Cloudflare Inc." \
  || { echo "インストーラーの署名を確認できませんでした。管理者に連絡してください。"; exit 1; }

write_mdm

sudo installer -pkg "$PKG" -target / >/dev/null
rm -f "$PKG"

# 個人向けの登録が先に入っていたら外して、会社のログインをやり直す
for _ in $(seq 1 20); do "$W" status >/dev/null 2>&1 && break; sleep 1; done
if "$W" registration show 2>/dev/null | grep -q "Account type: Free"; then
  "$W" registration delete >/dev/null 2>&1 || true
fi
open -a "Cloudflare WARP" 2>/dev/null || true
if ! "$W" registration show 2>/dev/null | grep -q "Organization: villegroup"; then
  "$W" registration new villegroup >/dev/null 2>&1 || true
fi

say "② ブラウザが開きます。会社メールを入れて「Send login code」→ 届いた6桁を入れる → 「開く」"
echo "   ブラウザが開かないときは https://villegroup.cloudflareaccess.com/warp を開いてください。"

for _ in $(seq 1 180); do
  if gateway_on; then
    say "✅ 完了！会社VPNにつながりました。#regular の案内に ✅ を押してください。"
    exit 0
  fi
  sleep 2
done
say "まだつながっていません。ブラウザで6桁のコードを入れて「開く」を押したか確認してください。"
