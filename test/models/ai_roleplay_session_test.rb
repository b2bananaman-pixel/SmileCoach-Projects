require "test_helper"

class AiRoleplaySessionTest < ActiveSupport::TestCase
  test "belongs to user" do
    session = ai_roleplay_sessions(:one)

    assert_equal users(:one), session.user
  end

  test "belongs to practice theme" do
    session = ai_roleplay_sessions(:one)

    assert_equal practice_themes(:one), session.practice_theme
  end

  test "has many ai roleplay messages" do
    session = ai_roleplay_sessions(:one)

    assert_equal 2, session.ai_roleplay_messages.count
  end

  test "destroys associated messages when destroyed" do
    session = ai_roleplay_sessions(:one)

    assert_difference("AiRoleplayMessage.count", -2) do
      session.destroy
    end
  end

  test "has one ai roleplay evaluation" do
    session = ai_roleplay_sessions(:one)

    assert_equal ai_roleplay_evaluations(:one),
                 session.ai_roleplay_evaluation
  end

  test "destroys associated evaluation when destroyed" do
    session = ai_roleplay_sessions(:one)

    assert_difference("AiRoleplayEvaluation.count", -1) do
      session.destroy!
    end
  end
end
