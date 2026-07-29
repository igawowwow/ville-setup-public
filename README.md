# ヴィレグループ スタートキット

新しいPCで**1行**実行すれば、ヴィレグループの業務に必要な環境が整う。

## Mac

```
curl -fsSL https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/install.sh | bash
```

途中で役割（1: dev / 2: sales / 3: back-office）とGitHub情報を聞かれる。10〜20分。

終わったらターミナルを閉じて開き直し、案内された `gh auth login` 等でログイン。
Slack・Google Drive はアプリを起動して会社アカウントでログイン。
社内のパスワードはGoogleパスワードマネージャー（会社のGoogleアカウントでChromeにログインすれば自動同期）。

確認だけしたい（何も変更しない）:
```
bash <(curl -fsSL https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/install.sh) --verify
```

環境がおかしくなったら:
```
vg-update
```

開発ツール（Xcode Command Line Tools）が入っていない場合、スクリプトが自動で
入れようとする。それでも入らないときは自動でブラウザが開き、Apple公式サイトから
直接ダウンロードする手順が表示されるので、その通りに進めてからもう一度1行目の
コマンドを実行すればよい（「このソフトウェアは現在、アップデートサーバから
入手できません」というダイアログ自体は無視してOK）。

## Windows（草案・実機未検証）

PowerShellを管理者権限で開いて：
```
irm https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/windows/install.ps1 | iex
```

困ったら Slack で管理者へ。自分でOS再インストールはしない。

---

このリポは配布専用。開発・管理は別のprivateリポで行っている。
