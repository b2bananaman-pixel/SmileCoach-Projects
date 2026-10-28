class Practice < ApplicationRecord
  has_one_attached :audio
  has_one_attached :video

  belongs_to :user
  belongs_to :practice_theme
  belongs_to :ai_roleplay_session, optional: true
  has_one :analysis, dependent: :destroy

  validates :ai_roleplay_session_id, uniqueness: true, allow_nil: true
  validate :ai_roleplay_session_matches_user_and_practice_theme

  private

  # 他ユーザーや別テーマのAIロープレに分析結果を紐付けないようにする
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
