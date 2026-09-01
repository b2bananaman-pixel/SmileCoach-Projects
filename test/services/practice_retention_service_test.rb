require "test_helper"

class PracticeRetentionServiceTest < ActiveSupport::TestCase
  test "14日以上経過した練習履歴が削除される" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )

    assert Practice.exists?(practice.id)

    deleted_count = PracticeRetentionService.delete_expired

    assert_not Practice.exists?(practice.id)
    assert_equal 1, deleted_count
  end

  test "14日未満の練習履歴は削除されない" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 13.days.ago
    )

    deleted_count = PracticeRetentionService.delete_expired

    assert Practice.exists?(practice.id)
    assert_equal 0, deleted_count
  end

  test "練習履歴を削除すると分析結果も削除される" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )

    analysis = Analysis.create!(
      practice: practice,
      total_score: 85
    )

    PracticeRetentionService.delete_expired

    assert_not Practice.exists?(practice.id)
    assert_not Analysis.exists?(analysis.id)
  end

  test "練習履歴を削除すると録音データも削除される" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )

    audio_path = Rails.root.join("test/fixtures/files/test_audio.webm")

    practice.audio.attach(
      io: File.open(audio_path),
      filename: "test_audio.webm",
      content_type: "audio/webm"
    )

    attachment_id = practice.audio.attachment.id

    assert practice.audio.attached?
    assert ActiveStorage::Attachment.exists?(attachment_id)

    PracticeRetentionService.delete_expired

    assert_not Practice.exists?(practice.id)
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
  end
end
