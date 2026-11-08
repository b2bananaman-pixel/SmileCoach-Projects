# 商材カテゴリの管理（物理削除は行わない）
class Admin::ProductCategoriesController < Admin::BaseController
  before_action :set_product_category, only: %i[edit update activate deactivate]

  def index
    @product_categories = ProductCategory.ordered
    @product_counts = Product.group(:product_category_id).count
  end

  def new
    @product_category = ProductCategory.new
  end

  def create
    @product_category = ProductCategory.new(product_category_params)

    if save_with_unique_name { @product_category.save }
      redirect_to admin_product_categories_path, notice: "カテゴリを登録しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # 編集画面を開いた時点のlock_versionを送信させ、他の管理者の変更を上書きしないようにする
  def update
    if save_with_unique_name { @product_category.update(product_category_update_params) }
      redirect_to admin_product_categories_path, notice: "カテゴリを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    @product_category.errors.add(:base, STALE_RECORD_MESSAGE)
    render :edit, status: :conflict
  end

  # 有効・無効はパラメータを受け取らず、このアクションでのみ切り替える
  def activate
    change_active(true, "「#{@product_category.name}」を有効にしました")
  end

  def deactivate
    change_active(false, "「#{@product_category.name}」を無効にしました")
  end

  private

  def set_product_category
    @product_category = ProductCategory.find(params[:id])
  end

  def product_category_params
    params.require(:product_category).permit(:name)
  end

  # lock_versionがない更新は、競合を検出できないため受け付けない（400を返す）
  def product_category_update_params
    params.require(:product_category).permit(:name, :lock_version).tap do |permitted|
      raise ActionController::ParameterMissing, :lock_version if permitted[:lock_version].blank?
    end
  end

  # 同時に同じ名前で登録された場合は、DBの一意制約のエラーを重複のエラーとして表示する
  def save_with_unique_name
    yield
  rescue ActiveRecord::RecordNotUnique
    @product_category.errors.add(:name, :taken)
    false
  end

  def change_active(active, notice)
    @product_category.update!(active: active)
    redirect_to admin_product_categories_path, notice: notice
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError
    redirect_to admin_product_categories_path, alert: "カテゴリの状態を変更できませんでした。画面を再読み込みしてから、もう一度操作してください。"
  end
end
