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

  test "音声分析用のPracticeがない場合はpracticeがnilになる" do
    session = ai_roleplay_sessions(:one)

    assert_nil session.practice
  end

  test "削除時に音声分析用のPracticeとAnalysisも削除する" do
    session = ai_roleplay_sessions(:one)

    practice = Practice.create!(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    practice.create_analysis!(
      speech_speed: 5.5,
      speech_speed_score: 100,
      filler_count: 0,
      filler_score: 100,
      volume: -15.0,
      volume_score: 100,
      total_score: 100
    )

    assert_difference(
      [ "Practice.count", "Analysis.count" ],
      -1
    ) do
      session.destroy!
    end
  end

  test "削除時に通常録画のPracticeは削除しない" do
    session = ai_roleplay_sessions(:one)

    assert_no_difference("Practice.count") do
      session.destroy!
    end

    assert Practice.exists?(practices(:one).id)
  end

  test "ユーザーのAIロープレを一括削除すると音声分析用Practiceも削除される" do
    session = ai_roleplay_sessions(:two)
    user = session.user

    Practice.create!(
      user: user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    # 音声分析用Practiceが先に削除され、外部キー違反にならないこと
    assert_difference("AiRoleplaySession.count", -1) do
      user.ai_roleplay_sessions.destroy_all
    end

    assert_not Practice.exists?(ai_roleplay_session_id: session.id)
  end
end
