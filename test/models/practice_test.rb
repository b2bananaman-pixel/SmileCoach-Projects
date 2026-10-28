require "test_helper"

class PracticeTest < ActiveSupport::TestCase
  test "practice can have an audio attachment" do
    practice = practices(:one)
    file = Rails.root.join("test/fixtures/files/test_audio.webm")

    practice.audio.attach(
      io: File.open(file),
      filename: "test_audio.webm",
      content_type: "audio/webm"
    )

    assert practice.audio.attached?
    assert_equal "test_audio.webm", practice.audio.filename.to_s
    assert_equal "audio/webm", practice.audio.content_type
  end

  test "practice can retrieve attached audio" do
    practice = practices(:one)
    file = Rails.root.join("test/fixtures/files/test_audio.webm")

    practice.audio.attach(
      io: File.open(file),
      filename: "test_audio.webm",
      content_type: "audio/webm"
    )

    assert practice.audio.attached?
    assert_equal "test_audio.webm", practice.audio.filename.to_s
  end

  test "practice belongs to a user and a practice theme" do
    practice = practices(:one)

    assert_equal users(:one), practice.user
    assert_equal practice_themes(:one), practice.practice_theme
  end

  test "通常録画のPracticeはAIロープレに関連付けなくても保存できる" do
    practice = Practice.new(
      user: users(:one),
      practice_theme: practice_themes(:one)
    )

    assert practice.valid?
    assert_nil practice.ai_roleplay_session
  end

  test "PracticeをAIロープレに関連付けられる" do
    session = ai_roleplay_sessions(:one)

    practice = Practice.create!(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    assert_equal session, practice.ai_roleplay_session
    assert_equal practice, session.reload.practice
  end

  test "1つのAIロープレに複数のPracticeを関連付けられない" do
    session = ai_roleplay_sessions(:one)

    Practice.create!(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    duplicate = Practice.new(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    assert_not duplicate.valid?
    assert duplicate.errors.added?(:ai_roleplay_session_id, :taken, value: session.id)
  end

  test "他ユーザーのAIロープレにはPracticeを関連付けられない" do
    session = ai_roleplay_sessions(:two)

    practice = Practice.new(
      user: users(:one),
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    assert_not practice.valid?
    assert_includes(
      practice.errors[:ai_roleplay_session],
      "は練習したユーザーのAIロープレではありません"
    )
  end

  test "別テーマのAIロープレにはPracticeを関連付けられない" do
    session = ai_roleplay_sessions(:one)

    practice = Practice.new(
      user: session.user,
      practice_theme: practice_themes(:two),
      ai_roleplay_session: session
    )

    assert_not practice.valid?
    assert_includes(
      practice.errors[:ai_roleplay_session],
      "は同じ練習テーマのAIロープレではありません"
    )
  end
end
