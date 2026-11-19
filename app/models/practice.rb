class Practice < ApplicationRecord
  has_one_attached :audio
  has_one_attached :video

  belongs_to :user
  # 商材を起点としたAIロープレの音声分析では練習テーマを使わないため任意とする（通常録画では必須）
  belongs_to :practice_theme, optional: true
  belongs_to :ai_roleplay_session, optional: true
  has_one :analysis, dependent: :destroy

  validates :practice_theme, presence: true, if: -> { ai_roleplay_session_id.nil? }
  validates :ai_roleplay_session_id, uniqueness: true, allow_nil: true
  validate :ai_roleplay_session_matches_user_and_practice_theme

  private

  # 他ユーザーや別テーマのAIロープレに分析結果を紐付けないようにする
  #
  # 商材を起点としたAIロープレ（練習テーマなし）では、Practiceも練習テーマなしとする。
  def ai_roleplay_session_matches_user_and_practice_theme
    return if ai_roleplay_session.nil?

    if ai_roleplay_session.user_id != user_id
      errors.add(:ai_roleplay_session, "は練習したユーザーのAIロープレではありません")
    end

    if ai_roleplay_session.practice_theme_id != practice_theme_id
      errors.add(:ai_roleplay_session, "は同じ練習テーマのAIロープレではありません")
    end
  end
end
