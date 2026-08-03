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
  "GitHub.cli"
)
foreach ($id in $core) {
  Write-Host "  導入中: $id"
  winget install --id $id --silent --accept-package-agreements --accept-source-agreements -e 2>$null
}
Ok "共通アプリ完了"

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
Write-Host "    - gh auth login  でGitHubにログイン"
Write-Host "    - Slack / Google Drive を起動して会社アカウントでログイン"
Write-Host "    - Chromeで会社のGoogleアカウントにログイン（パスワードは自動同期）"
