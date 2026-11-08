require "test_helper"

# db/seeds.rbの初期カテゴリの登録を確認する
class SeedsTest < ActiveSupport::TestCase
  setup do
    Product.delete_all
    ProductCategory.delete_all
  end

  test "初期カテゴリ4種類を有効な状態で登録し、再実行しても重複しない" do
    load_seeds

    assert_equal ProductCategory::DEFAULT_NAMES.sort, ProductCategory.pluck(:name).sort
    assert ProductCategory.all.all?(&:active?)

    assert_no_difference("ProductCategory.count") { load_seeds }
  end

  test "再実行しても、管理者が無効にしたカテゴリの状態を変更しない" do
    load_seeds
    ProductCategory.find_by!(name: "カード").update!(active: false)

    load_seeds

    assert_not ProductCategory.find_by!(name: "カード").active?
  end

  test "再実行しても、練習テーマは重複しない" do
    load_seeds

    assert_no_difference("PracticeTheme.count") { load_seeds }
  end

  private

  def load_seeds
    Rails.application.load_seed
  end
end
