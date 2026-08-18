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
end
