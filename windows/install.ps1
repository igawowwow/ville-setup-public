# ==========================================================
#  ヴィレグループ Windows スタートキット（草案・未実機検証）
#
#  使い方（社員）:
#    irm https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/windows/install.ps1 | iex
#
#  ※ 現時点ではWindows実機での動作確認前。Windows使用の社員と一緒に
#     初回実行して、エラー箇所を直してから全社展開すること。
# ==========================================================

$ErrorActionPreference = "Stop"

function Step($msg)  { Write-Host "`n[$msg]" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "  OK  $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "  !   $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "  x   $msg" -ForegroundColor Red }

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  ヴィレグループ Windows スタートキット" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# ---------- winget の確認 ----------
Step "winget の確認"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  Fail "winget が見つからない。Microsoft Store から「アプリ インストーラー」を更新してから再実行してください"
  exit 1
}
Ok "winget: $(winget --version)"

# ---------- プロファイル選択 ----------
Step "役割（プロファイル）を選ぶ"
Write-Host "   1) dev          … エンジニア"
Write-Host "   2) sales        … 営業"
Write-Host "   3) back-office  … 労務・経理"
$choice = Read-Host "番号を入力 (デフォルト: 2)"
switch ($choice) {
  "1" { $Profile = "dev" }
  "3" { $Profile = "back-office" }
  default { $Profile = "sales" }
}
Ok "プロファイル: $Profile"

# ---------- 共通アプリ ----------
Step "共通アプリを導入"
$core = @(
  "Google.Chrome",
  "SlackTechnologies.Slack",
  "Google.GoogleDrive",
  "Git.Git",
  "GitHub.cli",
  "Cloudflare.Warp"
)
foreach ($id in $core) {
  Write-Host "  導入中: $id"
  winget install --id $id --silent --accept-package-agreements --accept-source-agreements -e 2>$null
}
Ok "共通アプリ完了"

# ---------- 会社VPN(Cloudflare WARP)をチームに接続 ----------
Step "会社VPN（WARP）を villegroup に自動接続"
try {
  $rk = "HKLM:\SOFTWARE\Cloudflare\Warp"
  New-Item -Path $rk -Force | Out-Null
  New-ItemProperty -Path $rk -Name "organization" -Value "villegroup" -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $rk -Name "auto_connect"  -Value 1          -PropertyType DWord  -Force | Out-Null
  New-ItemProperty -Path $rk -Name "service_mode"  -Value "warp"      -PropertyType String -Force | Out-Null
  Ok "WARP設定を配置（起動→会社メールでログインするだけ）"
} catch {
  Warn "WARP自動設定に失敗（管理者権限が必要）。WARPアプリを開きチーム名 villegroup を手入力してください"
}

# ---------- プロファイル別アプリ ----------
Step "役割別アプリを導入 ($Profile)"
$profileApps = switch ($Profile) {
  "dev" { @("Microsoft.VisualStudioCode", "OpenJS.NodeJS.LTS", "Python.Python.3.12", "Google.CloudSDK") }
  "back-office" { @("Zoom.Zoom", "TheDocumentFoundation.LibreOffice", "Adobe.Acrobat.Reader.64-bit") }
  default { @("Zoom.Zoom", "TheDocumentFoundation.LibreOffice") }
}
foreach ($id in $profileApps) {
  Write-Host "  導入中: $id"
  winget install --id $id --silent --accept-package-agreements --accept-source-agreements -e 2>$null
}
Ok "役割別アプリ完了"

# ---------- セキュリティ一式 ----------
Step "セキュリティ設定"
try {
  Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
  Ok "ファイアウォール: オン"
} catch { Warn "ファイアウォールの設定に失敗（管理者権限で開き直して再実行）" }
try {
  Set-MpPreference -DisableRealtimeMonitoring $false -PUAProtection Enabled
  Update-MpSignature -ErrorAction SilentlyContinue
  Ok "Microsoft Defender: リアルタイム保護オン・不要アプリもブロック"
} catch { Warn "Defenderの設定に失敗（別のウイルス対策ソフトが入っている可能性）" }
try {
  $au = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
  New-Item -Path $au -Force | Out-Null
  Set-ItemProperty -Path $au -Name NoAutoUpdate -Value 0 -Type DWord
  Set-ItemProperty -Path $au -Name AUOptions -Value 4 -Type DWord
  Ok "Windows Update: 自動でダウンロード・インストール"
} catch { Warn "Windows Update の設定に失敗" }
try {
  $sys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
  Set-ItemProperty -Path $sys -Name InactivityTimeoutSecs -Value 300 -Type DWord
  Set-ItemProperty -Path $sys -Name legalnoticecaption -Value "ヴィレグループ 業務用PC"
  Set-ItemProperty -Path $sys -Name legalnoticetext -Value "拾われた方は 050-1720-8945 までご連絡ください。"
  Ok "5分操作がなければ自動ロック・ログイン画面に落とし物の連絡先"
} catch { Warn "画面ロックの設定に失敗" }
try { net user guest /active:no | Out-Null; Ok "ゲストアカウント: オフ" } catch { }
try {
  $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
  if ($bl.ProtectionStatus -eq 'On') { Ok "ディスク暗号化（BitLocker）: オン" }
  else { Warn "ディスク暗号化がオフ → 設定 > プライバシーとセキュリティ > デバイスの暗号化 をオン（回復キーはMicrosoftアカウントに保存）"; Start-Process "ms-settings:deviceencryption" }
} catch { Warn "ディスク暗号化を確認できない（Windows Home は 設定 > デバイスの暗号化 を確認）" }

# ---------- Villesee（勤怠の見える化アプリ） ----------
Step "Villesee"
try {
  $base = 'https://zxstlygsulxsdpehvsua.supabase.co/storage/v1/object/public/agent'
  $l = Invoke-RestMethod "$base/latest.json?t=$(Get-Random)"
  $p = $l.platforms.'windows-x86_64'
  $f = Join-Path $env:TEMP 'villsee-setup.exe'
  Invoke-WebRequest $p.url -OutFile $f -UseBasicParsing
  if ((Get-FileHash $f -Algorithm SHA256).Hash.ToLower() -ne $p.sha256) { throw 'ダウンロードが壊れていた' }
  Get-Process 'villsee-agent' -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Process $f -ArgumentList '/S' -Wait
  $exe = Get-ChildItem "$env:LOCALAPPDATA\Programs","$env:ProgramFiles" -Recurse -Filter 'villsee-agent.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($exe) { Start-Process $exe.FullName }
  Ok "Villesee $($l.version) を導入・起動（以後は自動で最新になる）"
} catch { Warn "Villesee の導入に失敗: $($_.Exception.Message)（もう一度このコマンドを実行）" }

# ---------- Claude Code ----------
Step "Claude Code"
if (Get-Command claude -ErrorAction SilentlyContinue) {
  Ok "既に導入済み"
} else {
  Warn "Claude Code の導入は現状 winget未対応。手動で https://claude.ai/download からインストールしてください"
}

# ---------- Git設定 ----------
Step "Git の名前とメール"
$curName = git config --global user.name 2>$null
$curMail = git config --global user.email 2>$null
if ($curName -and $curMail) {
  Ok "設定済み: $curName <$curMail>"
} else {
  $gn = Read-Host "GitHubのユーザー名"
  $gm = Read-Host "会社メールアドレス"
  git config --global user.name  $gn
  git config --global user.email $gm
  Ok "設定した: $gn <$gm>"
}

# ---------- 完了 ----------
Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "  セットアップ完了（要: 実機での動作確認）" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host "  次にやること:"
Write-Host "    - 会社VPN(WARP): 起動して Login with Cloudflare Zero Trust -> 会社メール(@ville-ville.com) -> 届いたコード入力"
Write-Host "    - gh auth login  でGitHubにログイン"
Write-Host "    - Slack / Google Drive を起動して会社アカウントでログイン"
Write-Host "    - Chromeで会社のGoogleアカウントにログイン（パスワードは自動同期）"
