# 商材情報の管理（物理削除は行わない）
class Admin::ProductsController < Admin::BaseController
  # 公開状態（published）はフォームから変更させず、publish・unpublishでのみ切り替える
  PERMITTED_ATTRIBUTES = %i[
    product_category_id maker name official_url summary
    features pricing precautions proposal_points confirmation_items
  ].freeze

  before_action :set_product, only: %i[show edit update publish unpublish]

  def index
    @products = Product.includes(:product_category).order(id: :desc)
  end

  def show
  end

  def new
    @product = Product.new
  end

  def create
    @product = Product.new(product_params)

    if @product.save
      redirect_to admin_product_path(@product), notice: "商材を登録しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # 編集画面を開いた時点のlock_versionを送信させ、他の管理者の変更を上書きしないようにする
  def update
    if @product.update(product_update_params)
      redirect_to admin_product_path(@product), notice: "商材を更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    @product.errors.add(:base, STALE_RECORD_MESSAGE)
    render :edit, status: :conflict
  end

  # 公開・非公開はパラメータを受け取らず、このアクションでのみ切り替える
  def publish
    change_published(true, "商材を公開しました")
  end

  def unpublish
    change_published(false, "商材を非公開にしました")
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(*PERMITTED_ATTRIBUTES)
  end

  # lock_versionがない更新は、競合を検出できないため受け付けない（400を返す）
  def product_update_params
    params.require(:product).permit(*PERMITTED_ATTRIBUTES, :lock_version).tap do |permitted|
      raise ActionController::ParameterMissing, :lock_version if permitted[:lock_version].blank?
    end
  end

  def change_published(published, notice)
    @product.update!(published: published)
    redirect_to admin_product_path(@product), notice: notice
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError
    redirect_to admin_product_path(@product), alert: "公開状態を変更できませんでした。画面を再読み込みしてから、もう一度操作してください。"
  end
end
