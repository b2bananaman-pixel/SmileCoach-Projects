# 商材の初期カテゴリだけを登録する
#
# 本番環境ではdb:seedを実行すると練習テーマの説明文も上書きされるため、初期カテゴリの登録にはこのタスクを使う。
# 既存のカテゴリは更新しないため、再実行しても重複せず、管理者が設定した有効・無効の状態も変わらない。
#
# 実行例:
#   bin/rails product_categories:seed_defaults
namespace :product_categories do
  desc "商材の初期カテゴリを登録する（既存のカテゴリは変更しない）"
  task seed_defaults: :environment do
    created_count = ProductCategory.seed_defaults!

    puts "初期カテゴリを#{created_count}件登録しました（カテゴリの総数: #{ProductCategory.count}件）"
  end
end
