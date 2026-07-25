# ヴィレグループ スタートキット

新しいPCで**1行**実行すれば、ヴィレグループの業務に必要な環境が整う。

## Mac

```
curl -fsSL https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/install.sh | bash
```

途中で役割（1: dev / 2: sales / 3: back-office）とGitHub情報を聞かれる。10〜20分。

終わったらターミナルを閉じて開き直し、案内された `gh auth login` 等でログイン。
Slack・Google Drive はアプリを起動して会社アカウントでログイン。
社内のパスワードは 1Password（招待メールから参加）。

確認だけしたい（何も変更しない）:
```
bash <(curl -fsSL https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/install.sh) --verify
```

環境がおかしくなったら:
```
vg-update
```

「このソフトウェアは現在、アップデートサーバから入手できません」と出たら:
① 日付と時刻の自動設定がON ② Apple IDにサインイン済み ③ スクリーンタイムの
「コンテンツとプライバシーの制限」がOFF — の3つを確認。それでもダメなら:
```
open "https://developer.apple.com/download/all/?q=Command+Line+Tools"
```
でApple公式サイトから直接ダウンロードしてインストール。

## Windows（草案・実機未検証）

PowerShellを管理者権限で開いて：
```
irm https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/windows/install.ps1 | iex
```

困ったら Slack で管理者へ。自分でOS再インストールはしない。

---

このリポは配布専用。開発・管理は別のprivateリポで行っている。
