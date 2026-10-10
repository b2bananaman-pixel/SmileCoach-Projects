class AiRoleplayEvaluation < ApplicationRecord
  belongs_to :ai_roleplay_session

  SCORE_ATTRIBUTES = %i[
    hearing_score
    listening_score
    needs_score
    proposal_score
    closing_score
  ].freeze

  SCORE_ATTRIBUTES.each do |attribute|
    validates attribute,
              numericality: {
                only_integer: true,
                in: 1..5
              },
              allow_nil: true
  end

  validates :reference_score,
            numericality: {
              only_integer: true,
              in: 0..100
            },
            allow_nil: true

  validates :ai_roleplay_session_id,
            uniqueness: true
end
