class Practice < ApplicationRecord
  has_one_attached :audio
  has_one_attached :video

  belongs_to :user
  belongs_to :practice_theme
  has_one :analysis, dependent: :destroy
end
