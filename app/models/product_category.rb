class ProductCategory < ApplicationRecord
  # 初期カテゴリ（db/seeds.rbとproduct_categories:seed_defaultsで登録する）
  DEFAULT_NAMES = %w[インターネット カード ネットテレビ その他].freeze

  has_many :products, dependent: :restrict_with_error

  # 前後の空白を除去し、全角・半角の表記ゆれをNFKCで統一してから保存・検索する
  # （全角スペースもNFKCで半角スペースになるため、stripで除去される）
  normalizes :name, with: ->(name) { name.unicode_normalize(:nfkc).strip }

  # 大文字・小文字の違いは、DBのLOWER(name)の一意インデックスと同じく重複として扱う
  validates :name, presence: true, length: { maximum: 50 }, uniqueness: { case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:id) }

  # 商材のカテゴリの選択肢
  #
  # 新規登録では有効なカテゴリだけを表示する。編集では、保存済みのカテゴリが無効でも選択肢に含め、関連付けを維持できるようにする。
  def self.selectable_for(product)
    current_id = product.product_category_id_in_database
    scope = active
    scope = scope.or(where(id: current_id)) if current_id
    scope.ordered
  end

  # 初期カテゴリを登録する
  #
  # 既存のカテゴリは更新しないため、再実行しても重複せず、管理者が設定した有効・無効の状態も変更しない。
  def self.seed_defaults!
    DEFAULT_NAMES.count do |name|
      normalized_name = normalize_value_for(:name, name)
      next false if where("LOWER(name) = LOWER(?)", normalized_name).exists?

      create!(name: normalized_name)
      true
    end
  end

  def display_name
    active? ? name : "#{name}（無効）"
  end
end
