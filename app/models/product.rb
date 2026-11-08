class Product < ApplicationRecord
  TEXT_MAXIMUM_LENGTH = 5000

  belongs_to :product_category

  normalizes :name, :summary, with: ->(value) { value.strip }
  normalizes :maker, :official_url, with: ->(value) { value.strip.presence }

  validates :name, presence: true, length: { maximum: 100 }
  validates :maker, length: { maximum: 100 }
  validates :official_url, length: { maximum: 500 }
  validates :summary, presence: true, length: { maximum: 1000 }
  validates :features, :pricing, :precautions, :proposal_points, :confirmation_items,
            length: { maximum: TEXT_MAXIMUM_LENGTH }
  validate :official_url_must_be_http
  # 保存済みのカテゴリが後から無効になっても、既存の商材は編集・公開の切り替えができるよう、
  # 新規登録とカテゴリを変更する場合だけ、有効なカテゴリかを確認する
  validate :product_category_must_be_active, if: -> { new_record? || will_save_change_to_product_category_id? }

  scope :published, -> { where(published: true) }
  scope :unpublished, -> { where(published: false) }

  # リンクとして表示する公式サイトURL
  #
  # 保存時に検証済みだが、検証を通さずに保存されたデータがあってもjavascript:などをリンクにしないよう、表示時にも確認する。
  def official_url_for_link
    uri = parse_http_url(official_url)
    uri&.to_s
  end

  private

  # http・httpsで、ホストがあるURLだけを返す
  def parse_http_url(url)
    return if url.blank?

    uri = URI.parse(url)
    uri if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end

  # リンクとして表示するため、javascript:などのURLを保存しないようにする
  def official_url_must_be_http
    return if official_url.blank? || parse_http_url(official_url)

    errors.add(:official_url, :invalid_url)
  end

  def product_category_must_be_active
    return if product_category.nil? || product_category.active?

    errors.add(:product_category, :inactive)
  end
end
