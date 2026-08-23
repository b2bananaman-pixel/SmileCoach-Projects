#!/bin/bash
set -e

# Rails の server.pid を削除（既存のプロセスIDファイルがあれば削除）
rm -f /app/tmp/pids/server.pid

# コンテナのメインプロセスを実行
exec "$@"
