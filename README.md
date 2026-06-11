# cursor-impl

A Claude Code skill that delegates implementation to parallel Cursor composer workers (headless `cursor-agent` CLI). Claude orchestrates: decompose, dispatch, review, integrate.

Claude Code を指示役(タスク分解・指示書作成・レビュー・統合)、Cursor Composer を実装役として並列実行する skill です。

## インストール

```bash
npx skills add Nasubikun/cursor-impl
```

または手動で:

```bash
git clone https://github.com/Nasubikun/cursor-impl ~/.claude/skills/cursor-impl
```

## 前提

- [Cursor CLI](https://cursor.com/cli)(`agent` コマンド)がインストール・ログイン済みであること
- Composer の実行は Cursor 側のプラン / 課金で行われます

## 使い方

Claude Code で、実装してほしい内容を添えて呼び出します:

```
/cursor-impl ブラウザで動くテトリスを作ってください
```

Claude が以下を実行します:

1. **Preflight**: working tree と lint / test コマンドの確認
2. **タスク分解**: 担当ファイルが重ならないように分割。共有部分は Claude が自分で書く
3. **指示書(brief)作成**: タスクごとに brief.md を書く
4. **並列ディスパッチ**: headless の Cursor CLI をバックグラウンドで並列実行
5. **レビュー**: Composer の自己報告は信用せず、Claude が変更ファイルを全部読み、lint / test も回す。問題があれば feedback.md を書いて差し戻し(最大 3 ラウンド)
6. **統合**: 全体の検証を回してレポート

タスクの成果物(brief / feedback / ログ / result.json)は対象リポジトリの `.claude/cursor-impl/<slug>/task-<n>/` に保存されます(git 管理外)。

## 設定

環境変数で上書きできます:

| 変数 | デフォルト | 説明 |
|---|---|---|
| `CURSOR_MODEL` | `composer-2.5-fast` | Composer のモデル ID |
| `CURSOR_AGENT_BIN` | `~/.local/bin/agent` | Cursor CLI のパス |

## 検証記事

この skill を使った「Fable 5 に指示させて下位モデルが実装すればいい、は本当か?」の検証記事はこちら: (TODO: Zenn 記事リンク)

## License

MIT
