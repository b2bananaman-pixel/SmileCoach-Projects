class AiRoleplaySession < ApplicationRecord
  belongs_to :user
  belongs_to :practice_theme

  has_many :ai_roleplay_messages, dependent: :destroy
  has_one_attached :video
end
