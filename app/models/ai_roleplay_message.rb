class AiRoleplayMessage < ApplicationRecord
  belongs_to :ai_roleplay_session

  validates :role, presence: true, inclusion: { in: %w[user assistant] }
  validates :content, presence: true
end
