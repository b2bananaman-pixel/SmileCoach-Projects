require "test_helper"

class AiRoleplayEvaluationTest < ActiveSupport::TestCase
  setup do
    @evaluation = ai_roleplay_evaluations(:one)
  end

  test "belongs to ai roleplay session" do
    assert_equal ai_roleplay_sessions(:one), @evaluation.ai_roleplay_session
  end

  test "saves evaluation with scores and feedback" do
    assert_predicate @evaluation, :valid?

    assert_equal 1, @evaluation.hearing_score
    assert_equal "MyText", @evaluation.hearing_good_point
    assert_equal "MyText", @evaluation.hearing_improvement_point
    assert_equal "MyText", @evaluation.overall_strength
    assert_equal "MyText", @evaluation.priority_improvement
    assert_equal "MyText", @evaluation.next_practice_goal
  end

  test "accepts scores from 1 to 5" do
    AiRoleplayEvaluation::SCORE_ATTRIBUTES.each do |attribute|
      (1..5).each do |score|
        @evaluation.public_send("#{attribute}=", score)

        assert_predicate @evaluation, :valid?,
                         "#{attribute} should accept #{score}"
      end
    end
  end

  test "rejects scores outside 1 to 5" do
    AiRoleplayEvaluation::SCORE_ATTRIBUTES.each do |attribute|
      [ 0, 6, -1 ].each do |score|
        @evaluation.public_send("#{attribute}=", score)

        assert_not @evaluation.valid?,
                   "#{attribute} should reject #{score}"

        @evaluation.public_send("#{attribute}=", 1)
      end
    end
  end

  test "allows nil scores for not applicable categories" do
    AiRoleplayEvaluation::SCORE_ATTRIBUTES.each do |attribute|
      @evaluation.public_send("#{attribute}=", nil)
    end

    assert_predicate @evaluation, :valid?
  end

  test "accepts reference score from 0 to 100" do
    [ 0, 50, 100 ].each do |score|
      @evaluation.reference_score = score

      assert_predicate @evaluation, :valid?,
                       "reference_score should accept #{score}"
    end
  end

  test "rejects reference score outside 0 to 100" do
    [ -1, 101 ].each do |score|
      @evaluation.reference_score = score

      assert_not @evaluation.valid?,
                 "reference_score should reject #{score}"
    end
  end

  test "allows nil reference score" do
    @evaluation.reference_score = nil

    assert_predicate @evaluation, :valid?
  end

  test "does not allow duplicate evaluation for same session" do
    duplicate = AiRoleplayEvaluation.new(
      ai_roleplay_session: ai_roleplay_sessions(:one),
      hearing_score: 3
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names,
                    :ai_roleplay_session_id
  end

  test "session has one evaluation" do
    session = ai_roleplay_sessions(:one)

    assert_equal @evaluation, session.ai_roleplay_evaluation
  end

  test "defines five categories with Japanese labels in display order" do
    assert_equal(
      {
        hearing: "ヒアリング",
        listening: "傾聴",
        needs: "ニーズ把握",
        proposal: "提案",
        closing: "クロージング"
      },
      AiRoleplayEvaluation::CATEGORY_LABELS
    )
  end

  test "converts scores from 1 to 5 into display points, stars and faces" do
    expected = {
      1 => [ 20, "★", "😟" ],
      2 => [ 40, "★★", "😕" ],
      3 => [ 60, "★★★", "😐" ],
      4 => [ 80, "★★★★", "🙂" ],
      5 => [ 100, "★★★★★", "😊" ]
    }

    AiRoleplayEvaluation::CATEGORY_LABELS.each_key do |category|
      expected.each do |score, (points, stars, face)|
        @evaluation.public_send("#{category}_score=", score)

        assert_equal score, @evaluation.score_for(category)
        assert @evaluation.evaluated?(category)
        assert_equal points, @evaluation.points_for(category)
        assert_equal stars, @evaluation.stars_for(category)
        assert_equal face, @evaluation.face_for(category)
      end
    end
  end

  test "returns nil display values for not applicable categories" do
    AiRoleplayEvaluation::CATEGORY_LABELS.each_key do |category|
      @evaluation.public_send("#{category}_score=", nil)

      assert_not @evaluation.evaluated?(category)
      assert_nil @evaluation.points_for(category)
      assert_nil @evaluation.stars_for(category)
      assert_nil @evaluation.face_for(category)
    end
  end

  test "returns good point and improvement point for each category" do
    @evaluation.hearing_good_point = "質問できていました。"
    @evaluation.hearing_improvement_point = "深掘りしましょう。"

    assert_equal "質問できていました。", @evaluation.good_point_for(:hearing)
    assert_equal "深掘りしましょう。", @evaluation.improvement_point_for(:hearing)
  end

  test "destroys evaluation when session is destroyed" do
    session = ai_roleplay_sessions(:one)

    assert_difference("AiRoleplayEvaluation.count", -1) do
      session.destroy!
    end
  end
end
