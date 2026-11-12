# バージョン管理

公開バージョン（例：`0.2.0`）とビルド番号を分けて管理します。

- `Config/Version.xcconfig`：Xcodeが参照するバージョン設定
- `VERSION`：公開バージョンを記録するファイル
- `Scripts/update_version.sh`：両ファイルをまとめて更新するスクリプト

`project.yml`からDebug・Release共通の設定を参照するため、XcodeとMakefileのどちらでビルドしても同じ番号になります。通常のビルドでは番号を変更しません。

## コマンド

| 操作 | コマンド |
| --- | --- |
| 現在の番号を確認 | `make version`（または `make show-version`） |
| 公開バージョンを更新 | `make bump-version VERSION=0.2.0` |
| ビルド番号だけ増やす | `make bump-build` |
| 両方を指定 | `make bump-version VERSION=0.2.0 BUILD_NUMBER=42` |
| 設定の整合性を確認 | `make check-version` |

Sparkleはビルド番号で更新を判定します。公開バージョンの変更時もビルド番号を1増やし、明示指定する場合は現在より大きい番号を使います。

スクリプトを直接呼び出す場合は、`./Scripts/update_version.sh 0.2.0 [ビルド番号]` または `./Scripts/update_version.sh --build-only` を使えます。更新はローカルファイルにのみ行い、Gitのコミットやタグ作成は行いません。

更新コマンドの動作検証は `make test-version` で実行できます。検証は一時ディレクトリで行い、プロジェクトの番号は変更しません。

## GitHub Releasesに配布

KeyDutyは、アプリに埋め込まれた `SUFeedURL` から更新情報を取得します。`project.yml` の `KEYDUTY_UPDATE_FEED_URL` は、`nissy/KeyDuty` の最新リリースに添付された `appcast.xml` を指しています。配布専用リポジトリを使う場合は、初回公開前にそのURLに変更します。配布先では、ユーザーが `appcast.xml` とDMGを認証なしでダウンロードできる必要があります。

1. `make bump-version VERSION=0.2.0` などで、公開する番号を設定します。
2. `make release` で署名付きDMGを作成します。`make notarize` で公証を申請し、`make notarize-status` で承認を確認してから `make notarize-staple` を実行します。
3. `make update-assets` で、最終版DMGと署名付き `appcast.xml` を `build/release/github/v0.2.0/` に用意します。
4. GitHub Releasesで `v0.2.0` の下書きを作り、両ファイルを添付してから最新の安定版として公開します。公開後は、更新情報とDMGをログインなしで取得できることを確認します。

Sparkleの秘密鍵は、作成したMacのログインキーチェーンにアカウント `com.nissy.KeyDuty` として保存されます。別のMacから署名する場合は、同じ鍵を安全に移行します。アプリには公開鍵だけを含めます。DMGやappcastを公開前に変更した場合は、最終版から配布ファイルを作り直してください。

初回はSparkle入りのDMGをインストールします。以後は設定の「一般」からアップデートを確認できます。定期確認は「一般」で有効にでき、インストールはユーザーの操作で始まります。

参考資料：[Sparkleの更新公開手順](https://sparkle-project.org/documentation/publishing/) · [GitHubのリリース公開手順](https://docs.github.com/ja/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
