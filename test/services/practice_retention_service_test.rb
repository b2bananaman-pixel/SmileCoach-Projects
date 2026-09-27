require "test_helper"

class PracticeRetentionServiceTest < ActiveSupport::TestCase
  test "14日を過ぎた練習履歴は残して文字起こしを削除する" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )

    processed_count = PracticeRetentionService.delete_expired

    assert Practice.exists?(practice.id)

    practice.reload

    assert_nil practice.transcription
    assert_equal 1, processed_count
  end

  test "14日未満の練習データは削除しない" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "まだ保持する文字起こしです",
      created_at: 13.days.ago
    )

    processed_count = PracticeRetentionService.delete_expired

    assert Practice.exists?(practice.id)
    assert_equal "まだ保持する文字起こしです", practice.reload.transcription
    assert_equal 0, processed_count
  end

  test "14日を過ぎても分析結果は残す" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )

    analysis = Analysis.create!(
      practice: practice,
      total_score: 85,
      ai_comment: "評価結果として残すコメントです"
    )

    PracticeRetentionService.delete_expired

    assert Practice.exists?(practice.id)
    assert Analysis.exists?(analysis.id)

    analysis.reload

    assert_equal 85, analysis.total_score
    assert_equal "評価結果として残すコメントです", analysis.ai_comment
  end

  test "14日を過ぎた録音データを削除する" do
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

    PracticeRetentionService.delete_expired

    assert Practice.exists?(practice.id)
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not practice.reload.audio.attached?
  end

  test "14日を過ぎた動画データを削除する" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )

    video_path = Rails.root.join("test/fixtures/files/test_audio.webm")

    practice.video.attach(
      io: File.open(video_path),
      filename: "test_video.webm",
      content_type: "video/webm"
    )

    attachment_id = practice.video.attachment.id

    assert practice.video.attached?

    PracticeRetentionService.delete_expired

    assert Practice.exists?(practice.id)
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not practice.reload.video.attached?
  end

  test "削除対象データがなくなった練習は次回実行時に処理件数へ含めない" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )

    audio_path = Rails.root.join("test/fixtures/files/test_audio.webm")

    practice.audio.attach(
      io: File.open(audio_path),
      filename: "test_audio.webm",
      content_type: "audio/webm"
    )

    first_processed_count = PracticeRetentionService.delete_expired
    second_processed_count = PracticeRetentionService.delete_expired

    assert_equal 1, first_processed_count
    assert_equal 0, second_processed_count

    assert Practice.exists?(practice.id)

    practice.reload

    assert_nil practice.transcription
    assert_not practice.audio.attached?
  end
end
