# Neon PostgreSQL バックアップ・復元手順書

SmileCoach の本番データベース（Neon Free PostgreSQL）について、バックアップの取得・検証・安全な復元テストの手順をまとめたドキュメントです。

- 最終更新：2026-11-01
- 対象：SmileCoach 本番DB（Neon）

> **重要**
> この手順書の「復元」は、**ネットワークを無効化した一時コンテナへの復元テスト**を指します。
> 本番DB（Neon）への直接復元は通常手順ではありません。必要になった場合は、別途慎重に判断してください（[8. 本番DBへの誤操作を防ぐ注意事項](#8-本番dbへの誤操作を防ぐ注意事項)を参照）。

## 目次

1. [バックアップ取得の目的と前提条件](#1-バックアップ取得の目的と前提条件)
2. [NEON_DATABASE_URL の安全な設定方法](#2-neon_database_url-の安全な設定方法)
3. [backup.sh によるバックアップ取得方法](#3-backupsh-によるバックアップ取得方法)
4. [バックアップファイルの検証方法](#4-バックアップファイルの検証方法)
5. [ネットワークを無効化した一時コンテナでの復元方法](#5-ネットワークを無効化した一時コンテナでの復元方法)
6. [復元したテーブル・レコード件数の確認方法](#6-復元したテーブルレコード件数の確認方法)
7. [復元テスト用コンテナの安全な削除方法](#7-復元テスト用コンテナの安全な削除方法)
8. [本番DBへの誤操作を防ぐ注意事項](#8-本番dbへの誤操作を防ぐ注意事項)
9. [今後の課題（外部保管・定期実行）](#9-今後の課題外部保管定期実行)

## 1. バックアップ取得の目的と前提条件

### 1-1. 目的

- Neon Free の本番DBのデータを、Neon の外（ローカル環境）にも保持する
- 誤操作・障害・サービス側の問題が起きても、データを確認・復旧できる状態にする
- バックアップファイルが「実際に復元できる」ことを定期的に確認する

### 1-2. 環境

| 項目 | 内容 |
| --- | --- |
| 本番DB | Neon Free PostgreSQL 18.6 |
| ローカル開発DB | Docker PostgreSQL 15（`docker-compose.yml` の `db` サービス） |
| バックアップツール | PostgreSQL 18 の `pg_dump`（`postgres:18` イメージ） |
| バックアップ形式 | custom 形式（`.dump`） |
| 保存先 | `~/smilecoach-backups/` |
| バックアップスクリプト | `~/smilecoach-backups/backup.sh` |
| 復元テスト環境 | `postgres:18` イメージ（実行時は PostgreSQL 18.6）の一時 Docker コンテナ（ネットワーク無効） |

### 1-3. 前提条件

- Docker が利用できること（`docker run` が実行できる）
- `postgres:18` イメージを取得できること
- Neon の接続文字列（接続URL）を Neon のダッシュボードから取得できること
- `~/smilecoach-backups/` がリポジトリの**外**にあること

### 1-4. バージョンに関する注意

- `pg_dump` は**接続先サーバーと同じか新しいメジャーバージョン**を使う必要があります。本番が 18.6 のため、PostgreSQL 18 の `pg_dump` を使います。
- PostgreSQL 18 で作成した custom 形式のダンプは、PostgreSQL 15 の `pg_restore` では読み込めない場合があります。
- そのため、**ローカル開発DB（PostgreSQL 15）には復元しません**。復元テストは PostgreSQL 18 の一時コンテナで行います。

## 2. NEON_DATABASE_URL の安全な設定方法

`backup.sh` は環境変数 `NEON_DATABASE_URL` から接続先を読み取ります。接続URLにはパスワードが含まれるため、次のルールを守ってください。

### 2-1. 守ること

- 接続URLをリポジトリ内のファイル（`.env`、`config/`、`docs/` など）に書かない
- 接続URLをコマンドライン引数として直接入力しない（シェル履歴に残るため）
- `echo` などで接続URLを画面に表示しない
- スクリーンショット・作業記録・Issue・PR に接続URLを載せない
- 作業が終わったら `unset` で環境変数を削除する

### 2-2. 設定方法（入力を画面に表示しない）

`read -rs` を使うと、入力内容が画面にもシェル履歴にも残りません。

```bash
read -rs -p "NEON_DATABASE_URL: " NEON_DATABASE_URL
echo
export NEON_DATABASE_URL
```

プロンプトが表示されたら、Neon のダッシュボードからコピーした接続URLを貼り付けて Enter を押します。

### 2-3. 設定できたかの確認（値は表示しない）

```bash
if [[ -n "${NEON_DATABASE_URL:-}" ]]; then echo "設定済み"; else echo "未設定"; fi
```

`echo "$NEON_DATABASE_URL"` のように値そのものを表示しないでください。

### 2-4. 作業後の削除

```bash
unset NEON_DATABASE_URL
```

ターミナルを閉じた場合も環境変数は消えます。

## 3. backup.sh によるバックアップ取得方法

### 3-1. スクリプトの処理内容

`~/smilecoach-backups/backup.sh` は次の処理を行います。

1. `NEON_DATABASE_URL` が未設定ならエラーで終了する
2. `umask 077` と `chmod 700` で、バックアップを本人だけが読める権限にする
3. 一時ファイル（`.neon_backup_XXXXXXXX`）を作成する
4. `postgres:18` コンテナで `pg_dump` を実行する
   - 接続URLは**標準入力経由**でコンテナに渡すため、`docker run` の引数や `docker inspect` には表示されない
   - オプション：`--format=custom --no-owner --no-acl`
5. 取得したファイルを `pg_restore --data-only --file=/dev/null` で読み取り検証する（DBへの書き込みは行わない）
6. 検証に成功したら `neon_YYYYMMDD_HHMMSS.dump` にリネームする（`mv -n` で既存ファイルは上書きしない）
7. 失敗した場合は `trap` で一時ファイルを削除する

### 3-2. 実行手順

```bash
# 1. 接続URLを設定（「2. NEON_DATABASE_URL の安全な設定方法」を参照）
read -rs -p "NEON_DATABASE_URL: " NEON_DATABASE_URL
echo
export NEON_DATABASE_URL

# 2. バックアップを取得
~/smilecoach-backups/backup.sh

# 3. 接続URLを削除（成功・失敗にかかわらず必ず実行）
unset NEON_DATABASE_URL
```

> **注意**
> `backup.sh` がエラーで終了した場合も、`NEON_DATABASE_URL` はシェルに残ったままです。
> 原因の調査や再実行を行う場合も、**作業を終えるときは必ず `unset NEON_DATABASE_URL` を実行**してください。
> 削除できたかは「2-3. 設定できたかの確認」のコマンドで `未設定` と表示されることで確認します。

### 3-3. 成功時の出力

```text
Neonバックアップを開始します...
バックアップ取得・読み取り検証成功
-rw------- 1 <ユーザー名> <グループ名> 38K <日時> /home/<ユーザー名>/smilecoach-backups/neon_YYYYMMDD_HHMMSS.dump
```

「バックアップ取得・読み取り検証成功」が表示されない場合は、バックアップは完了していません。エラー内容を確認してください（エラー内容を共有するときは、接続URLが含まれていないか確認してください）。

## 4. バックアップファイルの検証方法

`backup.sh` でも読み取り検証を行っていますが、保管前・復元前に次の確認を行います。以下のコマンドはすべて `--network none` で実行するため、Neon には接続しません。

### 4-1. ファイルの存在・サイズ・権限の確認

```bash
ls -lh ~/smilecoach-backups/
```

確認ポイント：

- 対象の `neon_YYYYMMDD_HHMMSS.dump` が存在する
- サイズが 0 ではなく、前回のバックアップと比べて極端に小さくない
- 権限が `-rw-------`（本人のみ読み書き可）になっている
- `.neon_backup_XXXXXXXX` という一時ファイルが残っていない

### 4-2. 対象ファイルの選択と存在確認

意図しないファイルを検証・復元しないよう、**ファイル名を目で確認してから明示的に指定**します。

1. バックアップファイルの一覧を表示し、使用するファイル名を確認します。

   ```bash
   ls -lh ~/smilecoach-backups/neon_*.dump
   ```

2. 確認したファイル名を変数に設定します（`YYYYMMDD_HHMMSS` は実際の日時に置き換えます）。

   ```bash
   DUMP_FILE="neon_YYYYMMDD_HHMMSS.dump"
   ```

3. ファイル名の形式と、ファイルが存在することを検証します。

   ```bash
   if [[ "$DUMP_FILE" =~ ^neon_[0-9]{8}_[0-9]{6}\.dump$ ]] && [[ -f "$HOME/smilecoach-backups/$DUMP_FILE" ]]; then
     echo "対象ファイル: $DUMP_FILE"
     ls -lh "$HOME/smilecoach-backups/$DUMP_FILE"
   else
     echo "エラー: ファイル名が不正、またはファイルが存在しません。以降の手順を中止してください。"
   fi
   ```

`エラー` と表示された場合や、表示されたファイル名・日時が意図したものと異なる場合は、以降の手順を実行しないでください。

### 4-3. アーカイブの目次（TOC）の確認

```bash
docker run --rm --network none \
  -v "$HOME/smilecoach-backups:/backups:ro" \
  postgres:18 \
  pg_restore --list "/backups/$DUMP_FILE" | grep -E 'TABLE DATA'
```

`users`、`practice_themes`、`practices`、`analyses`、`ai_roleplay_sessions` などのテーブルが `TABLE DATA` として含まれていることを確認します。

### 4-4. 全体の読み取り検証

```bash
docker run --rm --network none \
  -v "$HOME/smilecoach-backups:/backups:ro" \
  postgres:18 \
  pg_restore --file=/dev/null "/backups/$DUMP_FILE" && echo "読み取り検証成功"
```

### 4-5. チェックサムの記録（外部保管時の改ざん・破損確認用）

```bash
cd ~/smilecoach-backups
sha256sum "$DUMP_FILE" > "$DUMP_FILE.sha256"
sha256sum -c "$DUMP_FILE.sha256"
```

## 5. ネットワークを無効化した一時コンテナでの復元方法

### 5-1. 方針

復元テストは、以前実際に成功した次の構成に統一します。

| 項目 | 設定 |
| --- | --- |
| イメージ | `postgres:18`（実行時は PostgreSQL 18.6） |
| コンテナ名 | `smilecoach-restore-test` |
| ネットワーク | `--network none` |
| 一時データ領域 | `--tmpfs /var/lib/postgresql:rw,noexec,nosuid,size=256m` |
| ユーザー | `POSTGRES_USER=restore_user` |
| パスワード | `POSTGRES_PASSWORD=restore_test_only`（**テスト専用**。他の環境では使わない） |
| データベース | `POSTGRES_DB=restore_test_db` |
| ポート公開 | なし（`-p` を指定しない） |
| バックアップのマウント | `~/smilecoach-backups` を `/backups` に読み取り専用（`:ro`）でマウント |

- コンテナから外部（Neon を含む）に一切接続できないため、本番DBに誤って書き込むことがない
- ホストのポートを公開しないため、ローカル開発DBや他のコンテナにも影響しない
- 復元データは tmpfs（メモリ上の一時領域）に置く設計とする
  - `postgres:18` イメージのデータディレクトリ（`PGDATA`）は `/var/lib/postgresql/18/docker` で、イメージは親ディレクトリの `/var/lib/postgresql` をボリュームとして宣言している
  - そのため、`PGDATA` ではなく親の `/var/lib/postgresql` を `--tmpfs` に指定し、データディレクトリ全体が tmpfs の配下に入るようにしている
  - tmpfs の内容は、コンテナの停止時に破棄される
- 実際のマウント構成は Docker のバージョンや設定によって変わる可能性があるため、**起動後に「5-5. マウント構成（復元データの保存先）の確認」と「5-7. データディレクトリとバージョンの確認」で確認し、想定と異なる場合は復元を中止**する
- **本番DBの接続情報（`NEON_DATABASE_URL` など）は一切使用しない**。作業前に `unset NEON_DATABASE_URL` を実行しておく
- 対象ファイルは「4-2. 対象ファイルの選択と存在確認」で `DUMP_FILE` に設定・検証済みであること

### 5-2. 同名コンテナが存在しないことの確認

コンテナを作成する前に、同じ名前のコンテナが無いことを確認します。

```bash
docker ps -a --filter "name=^/smilecoach-restore-test$"
```

- ヘッダー行（`CONTAINER ID   IMAGE ...`）だけが表示されれば、同名コンテナはありません。次の手順に進みます。
- **コンテナが1件でも表示された場合は、削除・再利用せずに作業を中止**してください。以前の作業の残りか、別の用途のコンテナの可能性があるため、内容を確認してから対応を判断します。

### 5-3. 一時コンテナの起動

```bash
docker run -d \
  --name smilecoach-restore-test \
  --network none \
  --tmpfs /var/lib/postgresql:rw,noexec,nosuid,size=256m \
  -e POSTGRES_USER=restore_user \
  -e POSTGRES_PASSWORD=restore_test_only \
  -e POSTGRES_DB=restore_test_db \
  -v "$HOME/smilecoach-backups:/backups:ro" \
  postgres:18
```

> **一時データ領域の容量について**
> `size=256m` は、現在の小規模なバックアップ（数十KB程度）向けの設定です。
> データ量が増えた場合は、復元に必要な容量（テーブル・インデックスを含む）を見積もり、`size` を見直してください。容量が不足すると、復元が途中で失敗します。

### 5-4. ネットワーク設定の確認

```bash
docker inspect -f '{{.Name}} {{.Config.Image}} {{.HostConfig.NetworkMode}}' smilecoach-restore-test
```

`/smilecoach-restore-test postgres:18 none` と表示されることを確認します。**ネットワークが `none` 以外の場合は、以降の手順を実行せず、[7. 復元テスト用コンテナの安全な削除方法](#7-復元テスト用コンテナの安全な削除方法)に従ってコンテナを削除してください。**

> 5-4〜5-8 のコマンドは、確認結果を変数に保存して後の手順で使うため、**すべて同じターミナルで実行**してください。

### 5-5. マウント構成（復元データの保存先）の確認

復元データの保存先が想定どおり tmpfs になっているか、`docker inspect`（読み取り専用）で確認します。

想定するマウント構成は次のとおりです。

| 確認項目 | 想定する値 | 意味 |
| --- | --- | --- |
| `.Mounts`（ボリューム・バインドマウント） | `bind\|/backups\|false` の1件のみ | バックアップディレクトリの読み取り専用マウントだけがある。`volume` 型（匿名ボリュームなど）は無い |
| `.HostConfig.Tmpfs` | `{"/var/lib/postgresql":"rw,noexec,nosuid,size=256m"}` | `/var/lib/postgresql` が tmpfs になっている |
| 環境変数 `PGDATA` | `PGDATA=/var/lib/postgresql/18/docker` | データディレクトリが tmpfs の配下にある |

```bash
MOUNT_OK=""

CONTAINER_MOUNTS="$(docker inspect -f '{{range .Mounts}}{{.Type}}|{{.Destination}}|{{.RW}}{{println}}{{end}}' smilecoach-restore-test | sed '/^$/d')"
CONTAINER_TMPFS="$(docker inspect -f '{{json .HostConfig.Tmpfs}}' smilecoach-restore-test)"
CONTAINER_PGDATA="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' smilecoach-restore-test | grep '^PGDATA=')"

echo "Mounts: $CONTAINER_MOUNTS"
echo "Tmpfs:  $CONTAINER_TMPFS"
echo "$CONTAINER_PGDATA"

if [[ "$CONTAINER_MOUNTS" == "bind|/backups|false" ]] \
  && [[ "$CONTAINER_TMPFS" == '{"/var/lib/postgresql":"rw,noexec,nosuid,size=256m"}' ]] \
  && [[ "$CONTAINER_PGDATA" == "PGDATA=/var/lib/postgresql/18/docker" ]]; then
  MOUNT_OK="yes"
  echo "マウント構成OK"
else
  echo "エラー: 想定外のマウント構成です。復元を実行せずに中止してください。"
fi
```

- `PGDATA` 以外の環境変数は表示しません（`grep '^PGDATA='` で絞り込んでいます）
- `マウント構成OK` と表示されない場合は、**復元を実行せずに中止**し、表示内容を記録してから「7. 復元テスト用コンテナの安全な削除方法」に進みます
- 想定外の `volume` が見つかった場合も、`docker volume rm` などのボリューム操作は行いません。どのボリュームかを記録し、対応は別途判断します（開発用DBや他プロジェクトのボリュームを誤って削除しないため）

### 5-6. PostgreSQL の初期化完了待ち

`postgres:18` イメージは初回起動時に、初期化用の一時サーバーを起動して `restore_user` / `restore_test_db` を作成し、一度停止してから正式に起動し直します。`pg_isready` は初期化中の一時サーバーにも応答することがあるため、**初期化完了ログを確認してから** `pg_isready` を実行します。

判定に使うログは、`postgres:18` の初期化処理（`docker-entrypoint.sh`）が初期化の最後に出力する次の1行です。

```text
PostgreSQL init process complete; ready for start up.
```

データディレクトリが空の状態で起動するため、このコンテナは起動時に必ず初期化され、このログが出力されます。

次のコマンドで、最大60秒まで待機します。

```bash
RESTORE_READY=""
WAIT_RESULT="timeout"

for i in {1..60}; do
  CONTAINER_STATUS="$(docker inspect -f '{{.State.Status}}' smilecoach-restore-test 2>/dev/null || echo "not_found")"

  if [[ "$CONTAINER_STATUS" != "running" ]]; then
    WAIT_RESULT="container_${CONTAINER_STATUS}"
    break
  fi

  if docker logs smilecoach-restore-test 2>&1 | grep -qF "PostgreSQL init process complete; ready for start up." \
    && docker exec smilecoach-restore-test pg_isready -q -U restore_user -d restore_test_db; then
    RESTORE_READY="yes"
    WAIT_RESULT="ready"
    break
  fi

  sleep 1
done

if [[ "$RESTORE_READY" == "yes" ]]; then
  echo "初期化完了・接続可能"
else
  echo "エラー: 起動待ちに失敗しました（結果: $WAIT_RESULT）。復元を実行せずに中止してください。"
fi
```

| 表示 | 意味 | 対応 |
| --- | --- | --- |
| `初期化完了・接続可能` | 初期化が完了し、接続を受け付けている | 次の手順に進む |
| `結果: timeout` | 60秒以内に初期化が完了しなかった | 復元を実行せず中止する |
| `結果: container_exited` など | コンテナが異常終了した、または存在しない | 復元を実行せず中止する |

エラーの場合は、`docker logs smilecoach-restore-test` で原因を確認してから「7. 復元テスト用コンテナの安全な削除方法」に進みます（ログに秘密情報は含まれませんが、共有する前に内容を確認してください）。PCの負荷が高く60秒で足りない場合は、`{1..60}` の数値を増やします。

### 5-7. データディレクトリとバージョンの確認

PostgreSQL が実際に使っているデータディレクトリと、そのファイルシステムが tmpfs であることを、コンテナ内から確認します（読み取りのみ）。

```bash
DATA_DIR_OK=""

DATA_DIR="$(docker exec smilecoach-restore-test psql -U restore_user -d restore_test_db -tAc 'SHOW data_directory;')"
DATA_DIR_FSTYPE="$(docker exec smilecoach-restore-test df --output=fstype "$DATA_DIR" | tail -n 1 | tr -d ' ')"
SERVER_VERSION="$(docker exec smilecoach-restore-test psql -U restore_user -d restore_test_db -tAc 'SHOW server_version;')"

echo "data_directory: $DATA_DIR"
echo "filesystem:     $DATA_DIR_FSTYPE"
echo "server_version: $SERVER_VERSION"

if [[ "$DATA_DIR" == "/var/lib/postgresql/18/docker" ]] \
  && [[ "$DATA_DIR_FSTYPE" == "tmpfs" ]] \
  && [[ "$SERVER_VERSION" == 18.* ]]; then
  DATA_DIR_OK="yes"
  echo "データディレクトリ・バージョンOK"
else
  echo "エラー: データディレクトリまたはバージョンが想定と異なります。復元を実行せずに中止してください。"
fi
```

- `data_directory` が `/var/lib/postgresql/18/docker`、`filesystem` が `tmpfs`、`server_version` が `18.x`（前回の復元テストでは `18.6`）であることを確認します
- いずれかが異なる場合は、復元を実行せずに中止します

### 5-8. 復元直前の安全確認とバックアップの復元

`restore_test_db` はコンテナ起動時に作成済みのため、`createdb` は不要です。

復元の直前に、もう一度対象コンテナと前の手順の確認結果をまとめてチェックします。

```bash
PRECHECK_OK=""

TARGET_INFO="$(docker inspect -f '{{.Name}} {{.HostConfig.NetworkMode}} {{.State.Status}}' smilecoach-restore-test 2>/dev/null || echo "not_found")"
echo "対象コンテナ: $TARGET_INFO"
echo "復元ファイル: ${DUMP_FILE:-未設定}"

if [[ "$TARGET_INFO" == "/smilecoach-restore-test none running" ]] \
  && [[ "${MOUNT_OK:-}" == "yes" ]] \
  && [[ "${RESTORE_READY:-}" == "yes" ]] \
  && [[ "${DATA_DIR_OK:-}" == "yes" ]] \
  && [[ "${DUMP_FILE:-}" =~ ^neon_[0-9]{8}_[0-9]{6}\.dump$ ]] \
  && [[ -f "$HOME/smilecoach-backups/$DUMP_FILE" ]] \
  && [[ -z "${NEON_DATABASE_URL:-}" ]]; then
  PRECHECK_OK="yes"
  echo "安全確認OK"
else
  echo "エラー: 安全確認に失敗しました。復元を実行せずに中止してください。"
fi
```

チェック内容：

- コンテナ名が `/smilecoach-restore-test`、ネットワークが `none`、状態が `running` である
- 5-5（マウント構成）、5-6（初期化完了）、5-7（データディレクトリ・バージョン）の確認がすべて成功している
- 復元ファイル名の形式が正しく、ファイルが存在する（「4-2. 対象ファイルの選択と存在確認」と同じ条件）
- `NEON_DATABASE_URL` が設定されていない（本番の接続情報がシェルに残っていない）

`安全確認OK` と表示されたことを確認してから、復元を実行します。

```bash
if [[ "${PRECHECK_OK:-}" != "yes" ]]; then
  echo "エラー: 安全確認が完了していません。復元を中止します。"
else
  docker exec smilecoach-restore-test \
    pg_restore -U restore_user \
    --dbname=restore_test_db \
    --no-owner \
    --no-acl \
    --exit-on-error \
    "/backups/$DUMP_FILE" && echo "復元成功"
fi
```

- `--dbname` には**必ず一時コンテナ内のDB名（`restore_test_db`）**を指定します
- `--exit-on-error` により、エラーが発生した時点で停止します
- `復元成功` が表示されない場合は、エラー内容を記録してから「7. 復元テスト用コンテナの安全な削除方法」に進みます

## 6. 復元したテーブル・レコード件数の確認方法

> 個人情報保護のため、`SELECT *` などでレコードの中身（メールアドレス等）を表示しないでください。確認は**件数のみ**とします。

### 6-1. テーブル一覧の確認

```bash
docker exec smilecoach-restore-test \
  psql -U restore_user -d restore_test_db -c '\dt'
```

`db/schema.rb` の次のテーブルが存在することを確認します。

- `active_storage_attachments`
- `active_storage_blobs`
- `active_storage_variant_records`
- `ai_roleplay_evaluations`
- `ai_roleplay_messages`
- `ai_roleplay_sessions`
- `analyses`
- `practice_themes`
- `practices`
- `users`
- `schema_migrations` / `ar_internal_metadata`（Rails 管理用）

### 6-2. レコード件数の確認

```bash
docker exec smilecoach-restore-test \
  psql -U restore_user -d restore_test_db -c "
    SELECT 'users' AS table_name, COUNT(*) FROM users
    UNION ALL SELECT 'practice_themes', COUNT(*) FROM practice_themes
    UNION ALL SELECT 'practices', COUNT(*) FROM practices
    UNION ALL SELECT 'analyses', COUNT(*) FROM analyses
    UNION ALL SELECT 'ai_roleplay_sessions', COUNT(*) FROM ai_roleplay_sessions
    UNION ALL SELECT 'ai_roleplay_messages', COUNT(*) FROM ai_roleplay_messages
    UNION ALL SELECT 'ai_roleplay_evaluations', COUNT(*) FROM ai_roleplay_evaluations
    UNION ALL SELECT 'active_storage_blobs', COUNT(*) FROM active_storage_blobs
    UNION ALL SELECT 'active_storage_attachments', COUNT(*) FROM active_storage_attachments
    UNION ALL SELECT 'schema_migrations', COUNT(*) FROM schema_migrations;
  "
```

### 6-3. 確認ポイント

- エラーにならず、すべてのテーブルの件数が表示される
- 件数が本番の想定と大きく異なっていない

### 6-4. schema_migrations の確認

`schema_migrations` の件数と `db/migrate/` 内のファイル数は、**一致しなくても異常とは限りません**（本番へのデプロイ状況や、作業ブランチにしかないマイグレーションの有無によって変わるため）。単純な件数の一致は必須条件にしません。

必要に応じて、適用済みマイグレーションの内容を照合します。

1. 復元したDBで、最新の適用済みバージョンを確認します。

   ```bash
   docker exec smilecoach-restore-test \
     psql -U restore_user -d restore_test_db -c \
     "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 5;"
   ```

2. リポジトリ側（本番にデプロイされている main ブランチ）の最新マイグレーションを確認します。

   ```bash
   ls db/migrate | tail -n 5
   grep -E 'ActiveRecord::Schema\[.*\]\.define' db/schema.rb
   ```

3. 復元したDBの最新バージョンが、本番にデプロイ済みの `db/schema.rb` のバージョンと一致しているかを確認します。差がある場合は、未適用・未デプロイのマイグレーションが無いかを確認します。

### 6-5. 過去の復元テスト結果

| 実施日 | 復元環境 | 結果 | 確認内容 |
| --- | --- | --- | --- |
| 2026-10-30 | `postgres:18`（PostgreSQL 18.6）一時Dockerコンテナ | 成功 | `users` 2件、`practice_themes` 4件。テスト後に一時コンテナは削除済み |

復元テストを行ったら、この表に結果を追記してください。

## 7. 復元テスト用コンテナの安全な削除方法

**今回作成した専用コンテナ `smilecoach-restore-test` だけを削除します。** 既存の SmileCoach（`docker compose` の `db` / `web`）や他プロジェクトのコンテナ、ボリュームには触れません。

### 7-1. 削除対象の確認

```bash
docker ps -a --filter "name=^/smilecoach-restore-test$" --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
docker inspect -f '{{.Name}} {{.Config.Image}} {{.HostConfig.NetworkMode}}' smilecoach-restore-test
```

次の3点がすべて一致することを確認します。

| 項目 | 期待する値 |
| --- | --- |
| 名前 | `smilecoach-restore-test`（`docker inspect` では `/smilecoach-restore-test`） |
| イメージ | `postgres:18` |
| ネットワーク | `none` |

**1つでも異なる場合は削除せず、作業を中止して内容を確認してください。** 開発用の `db` サービスのコンテナ（`postgres:15`）は絶対に削除しないでください。

### 7-2. 停止と削除

```bash
docker stop smilecoach-restore-test
docker rm smilecoach-restore-test
```

- コンテナ名を必ず指定し、ワイルドカードや一括削除は使わない
- 5-5 で `volume` 型のマウントが無く、5-7 でデータディレクトリが tmpfs 上にあることを確認済みのため、復元データは `docker stop` の時点で tmpfs とともに破棄される想定
- ボリュームの削除（`docker rm -v` や `docker volume rm`）は行わない。5-5 で想定外のボリュームが見つかっていた場合も、ここでは削除せず、記録した内容をもとに別途判断する
- バックアップディレクトリは読み取り専用でマウントしているだけなので、`~/smilecoach-backups/` のファイルは削除されない

### 7-3. 削除後の確認

```bash
docker ps -a --filter "name=^/smilecoach-restore-test$"
ls -lh ~/smilecoach-backups/
```

- ヘッダー行だけが表示され、コンテナが一覧に無いこと
- バックアップファイルが残っていること

### 7-4. 実行してはいけないコマンド

次のコマンドは開発用DBのボリューム（`postgres_data`）や他プロジェクトのコンテナ・データを削除する可能性があるため、この手順では使用しません。

- `docker volume prune` / `docker volume rm`
- `docker container prune`
- `docker system prune`
- `docker compose down -v`
- `docker rm -f $(docker ps -aq)` などの一括削除

## 8. 本番DBへの誤操作を防ぐ注意事項

### 8-1. 基本ルール

- `NEON_DATABASE_URL` は **`backup.sh`（`pg_dump`：読み取りのみ）でだけ使用**する
- `pg_restore`、`psql`、`createdb`、`dropdb` などの書き込み系コマンドに `NEON_DATABASE_URL` を渡さない
- バックアップ取得後は、成功・失敗にかかわらず `unset NEON_DATABASE_URL` を実行し、その状態で復元テストを行う
- 復元テストは必ず `--network none` のコンテナ内で行い、[5-4](#5-4-ネットワーク設定の確認)と[5-8](#5-8-復元直前の安全確認とバックアップの復元)で `none` を確認してから実行する
- 復元テスト用のユーザー・パスワード・DB名（`restore_user` / `restore_test_only` / `restore_test_db`）はテスト専用とし、本番や開発環境では使わない
- `pg_restore --clean` / `--create` は、復元先が一時コンテナであることを確認できない限り使わない
- ローカル開発DB（`docker compose` の `db`）へは復元しない（バージョンが異なり、開発データも上書きされるため）

### 8-2. 本番DBへの直接復元について

本番DBへの直接復元は、**この手順書の通常手順の対象外**です。次の理由から、必要になった場合は別途慎重な判断が必要です。

- 現在の本番データが上書き・削除され、元に戻せなくなる可能性がある
- バックアップ取得後に追加・更新されたデータが失われる
- Active Storage のファイル（GCS）とDBのレコードの整合性が崩れる可能性がある

実施を検討する場合は、少なくとも次を事前に行ってください。

1. 実施直前の本番DBのバックアップを新たに取得し、検証する
2. 復元するバックアップを一時コンテナで復元テストし、内容を確認する
3. Neon 側の機能（ブランチ作成やポイントインタイムリストアなど）で対応できないか、プランの制限を含めて公式ドキュメントで確認する
4. 影響範囲・作業手順・切り戻し方法を文書化し、Issue として記録してから実施する

### 8-3. 秘密情報の取り扱い

- 接続URL、パスワード、APIキーを、ドキュメント・Issue・PR・コミット・作業記録に記載しない
- エラーメッセージやログを共有する前に、接続URLが含まれていないか確認する
- バックアップファイル（`.dump`）には本番の個人情報が含まれるため、リポジトリ内に置かない・コミットしない

## 9. 今後の課題（外部保管・定期実行）

現時点では、バックアップはローカル（WSL 上の `~/smilecoach-backups/`）にのみ保存しています。今後、次の項目を検討します。

### 9-1. 外部保管

- PC の故障・紛失に備え、ローカル以外の保管先（クラウドストレージなど）にもコピーを置く
- 外部に保管する前に、バックアップファイルを暗号化する（例：`gpg` や `age`）
- 暗号化の鍵・パスフレーズはバックアップと別の場所で管理する
- 外部保管後に `sha256sum -c` でファイルが破損していないことを確認する

### 9-2. 定期実行

- `cron` や systemd タイマーによる定期実行を検討する
  - WSL は PC が起動していないと動かないため、実行漏れに注意する
- GitHub Actions などで実行する場合は、接続URLを Secrets で管理し、ログに表示されないようにする
- 失敗時に気づける仕組み（通知など）を用意する

### 9-3. 保持期間（ローテーション）

- 何世代・何日分のバックアップを残すかを決める
- 古いバックアップの削除は手動で確認してから行う（自動削除を導入する場合は対象を限定する）

### 9-4. 録音・録画ファイルのバックアップ

- 本番環境の Active Storage は Google Cloud Storage（`config/storage.yml` の `google`）を使用しています
- **DBのバックアップには `active_storage_blobs` などのメタデータしか含まれず、録音・録画ファイルの実体は含まれません**
- GCS 側のファイルのバックアップ方法（バージョニング、別バケットへのコピーなど）を別途検討する

### 9-5. 復元テストの定期化

- 月1回など、定期的に「5〜7」の復元テストを行い、[6-5](#6-5-過去の復元テスト結果)の表に結果を記録する

### 9-6. 一時データ領域の容量見直し

- 復元テスト用の tmpfs（`size=256m`）は、現在の小規模なバックアップ向けの設定です
- データ量が増えた場合は、バックアップサイズと復元後のDBサイズを確認し、`size` を見直す（メモリ使用量が増えるため、PC のメモリ容量にも注意する）
