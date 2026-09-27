require "test_helper"

class PracticesTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
    Rake::Task["practices:delete_expired"].reenable
  end

  test "14日を過ぎた練習は履歴を残して文字起こしを削除する" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )

    Rake::Task["practices:delete_expired"].invoke

    assert Practice.exists?(practice.id)
    assert_nil practice.reload.transcription
  end

  test "14日未満の練習データは削除しない" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "まだ保持する文字起こしです",
      created_at: 13.days.ago
    )

    Rake::Task["practices:delete_expired"].invoke

    assert Practice.exists?(practice.id)
    assert_equal "まだ保持する文字起こしです", practice.reload.transcription
  end

  test "14日を過ぎても分析結果を残す" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )

    analysis = Analysis.create!(
      practice: practice,
      total_score: 85
    )

    Rake::Task["practices:delete_expired"].invoke

    assert Practice.exists?(practice.id)
    assert Analysis.exists?(analysis.id)
    assert_equal 85, analysis.reload.total_score
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

    Rake::Task["practices:delete_expired"].invoke

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

    Rake::Task["practices:delete_expired"].invoke

    assert Practice.exists?(practice.id)
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not practice.reload.video.attached?
  end
end
