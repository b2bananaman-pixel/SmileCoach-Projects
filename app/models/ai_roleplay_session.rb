class AiRoleplaySession < ApplicationRecord
  belongs_to :user
  belongs_to :practice_theme
  # 商材の選択は任意。product_snapshotには練習開始時点の商材情報を保存する
  belongs_to :product, optional: true

  has_many :ai_roleplay_messages, dependent: :destroy
  has_one :ai_roleplay_evaluation, dependent: :destroy
  has_one :practice, dependent: :destroy
  has_one_attached :video
end
