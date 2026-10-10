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

  test "destroys evaluation when session is destroyed" do
    session = ai_roleplay_sessions(:one)

    assert_difference("AiRoleplayEvaluation.count", -1) do
      session.destroy!
    end
  end
end
