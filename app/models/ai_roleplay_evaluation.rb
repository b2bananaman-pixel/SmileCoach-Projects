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

  CATEGORY_LABELS = {
    hearing: "ヒアリング",
    listening: "傾聴",
    needs: "ニーズ把握",
    proposal: "提案",
    closing: "クロージング"
  }.freeze

  POINTS_PER_SCORE = 20

  SCORE_FACES = {
    1 => "😟",
    2 => "😕",
    3 => "😐",
    4 => "🙂",
    5 => "😊"
  }.freeze

  def score_for(category)
    public_send("#{category}_score")
  end

  def evaluated?(category)
    !score_for(category).nil?
  end

  # DBの1〜5のスコアを、表示用の20〜100点へ換算する
  def points_for(category)
    score = score_for(category)
    return if score.nil?

    score * POINTS_PER_SCORE
  end

  def stars_for(category)
    score = score_for(category)
    return if score.nil?

    "★" * score
  end

  def face_for(category)
    SCORE_FACES[score_for(category)]
  end

  def good_point_for(category)
    public_send("#{category}_good_point")
  end

  def improvement_point_for(category)
    public_send("#{category}_improvement_point")
  end
end
