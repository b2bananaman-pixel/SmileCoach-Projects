require "test_helper"
require "rake"

class ProductCategoriesTaskTest < ActiveSupport::TestCase
  setup do
    # タスクを重複して読み込むと処理が複数回実行されるため、未定義の場合だけ読み込む
    Rails.application.load_tasks unless Rake::Task.task_defined?("product_categories:seed_defaults")
    Rake::Task["product_categories:seed_defaults"].reenable
  end

  test "初期カテゴリのうち未登録のものだけを登録する" do
    output, = capture_io do
      assert_difference("ProductCategory.count", 2) { Rake::Task["product_categories:seed_defaults"].invoke }
    end

    assert_includes output, "初期カテゴリを2件登録しました"
  end

  test "再実行しても重複せず、既存カテゴリの有効・無効の状態も変更しない" do
    product_categories(:internet).update!(active: false)
    capture_io { Rake::Task["product_categories:seed_defaults"].invoke }
    Rake::Task["product_categories:seed_defaults"].reenable

    output, = capture_io do
      assert_no_difference("ProductCategory.count") { Rake::Task["product_categories:seed_defaults"].invoke }
    end

    assert_includes output, "初期カテゴリを0件登録しました"
    assert_not product_categories(:internet).reload.active?
  end

  test "練習テーマを変更しない" do
    practice_theme = practice_themes(:one)

    assert_no_changes -> { [ PracticeTheme.count, practice_theme.reload.description ] } do
      capture_io { Rake::Task["product_categories:seed_defaults"].invoke }
    end
  end
end
