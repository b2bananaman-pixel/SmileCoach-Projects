class PracticeTheme < ApplicationRecord
  has_many :practices
  has_many :ai_roleplay_sessions, dependent: :destroy
end
