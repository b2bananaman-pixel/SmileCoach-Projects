class Product < ApplicationRecord
  TEXT_MAXIMUM_LENGTH = 5000

  # スナップショットの形式を変更した場合に、保存済みのデータと区別するためのバージョン
  ROLEPLAY_SNAPSHOT_VERSION = 1

  belongs_to :product_category
  # AIロープレの履歴がある商材は、履歴との関連付けを失わないよう削除できないようにする
  has_many :ai_roleplay_sessions, dependent: :restrict_with_error

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
  # AIロープレで選択できる商材（公開中で、カテゴリが有効なもの）
  scope :available_for_roleplay, -> { published.joins(:product_category).merge(ProductCategory.active) }

  # AIロープレの商材選択欄に表示する名前（商材名だけでは判別しづらいため、カテゴリ名・メーカー名を含める）
  def roleplay_label
    label = "#{product_category.name}／#{name}"
    maker.present? ? "#{label}（#{maker}）" : label
  end

  # AIロープレ開始時点の商材情報
  #
  # 練習後に商材が編集されても、練習時点の内容を確認できるように保存する。
  # JSONとして保存・暗号化するため、キーは文字列、日時はISO 8601形式の文字列とする。
  def roleplay_snapshot(captured_at: Time.current)
    {
      "version" => ROLEPLAY_SNAPSHOT_VERSION,
      "captured_at" => captured_at.iso8601(6),
      "product" => {
        "id" => id,
        "name" => name,
        "maker" => maker,
        "official_url" => official_url,
        "summary" => summary,
        "features" => features,
        "pricing" => pricing,
        "precautions" => precautions,
        "proposal_points" => proposal_points,
        "confirmation_items" => confirmation_items,
        "lock_version" => lock_version
      },
      "category" => {
        "id" => product_category.id,
        "name" => product_category.name
      }
    }
  end

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
