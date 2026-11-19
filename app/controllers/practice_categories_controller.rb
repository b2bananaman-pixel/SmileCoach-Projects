# 練習カテゴリの選択と、カテゴリ内の商材の選択（Issue #86）
#
# カテゴリ・商材は管理画面で登録したものを使い、有効なカテゴリと公開中の商材だけを表示する。
class PracticeCategoriesController < ApplicationController
  # 練習カテゴリIDの形式（正の整数）。"1abc" のような値が型変換で1として検索されないよう、先に確認する
  CATEGORY_ID_FORMAT = /\A[1-9][0-9]{0,18}\z/

  before_action :authenticate_user!

  # 公開中の商材が0件の有効なカテゴリも表示する
  def index
    @practice_categories = ProductCategory.active.ordered
    @product_counts = Product.available_for_roleplay.group(:product_category_id).count
  end

  # 無効なカテゴリ・存在しないカテゴリは404とする
  def show
    raise ActiveRecord::RecordNotFound unless params[:id].is_a?(String) && params[:id].match?(CATEGORY_ID_FORMAT)

    @practice_category = ProductCategory.active.find(params[:id])
    @products = Product.available_for_roleplay
                       .where(product_category: @practice_category)
                       .order(:name, :id)
  end
end
