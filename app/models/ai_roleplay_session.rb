class AiRoleplaySession < ApplicationRecord
  # 商材を起点としたAIロープレでは練習テーマを使わない（練習テーマを使った過去のセッションのために残す）
  # 練習テーマと商材のどちらも持たないセッションは、DBのチェック制約で作成できない
  belongs_to :practice_theme, optional: true
  belongs_to :user
  # product_snapshotには練習開始時点の商材情報を保存する
  belongs_to :product, optional: true

  has_many :ai_roleplay_messages, dependent: :destroy
  has_one :ai_roleplay_evaluation, dependent: :destroy
  has_one :practice, dependent: :destroy
  has_one_attached :video

  validate :practice_theme_or_product_present

  NO_PRODUCT_LABEL = "商材指定なし".freeze

  # 画面に表示するカテゴリ名（練習開始時点の商材情報から取得する。商材のない過去のセッションはnil）
  def roleplay_category_name
    snapshot_value("category", "name")
  end

  # 画面に表示する商材名（練習開始時点の商材情報から取得する。商材のない過去のセッションはnil）
  def roleplay_product_name
    snapshot_value("product", "name")
  end

  # 履歴などに表示する練習内容の名前
  #
  # 商材がある場合は「カテゴリ／商材名」、商材のない過去のセッションは練習テーマ名とする。
  def roleplay_title
    return [ roleplay_category_name, roleplay_product_name ].compact.join("／") if roleplay_product_name

    practice_theme&.name || NO_PRODUCT_LABEL
  end

  private

  def snapshot_value(*keys)
    return unless product_snapshot.is_a?(Hash)

    value = product_snapshot.dig(*keys)
    value.presence if value.is_a?(String)
  end

  def practice_theme_or_product_present
    return if practice_theme_id.present? || product_id.present?

    errors.add(:base, "練習テーマまたは商材を指定してください")
  end
end
