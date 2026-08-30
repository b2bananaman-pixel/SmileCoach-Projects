require "test_helper"

class PracticesTaskTest < ActiveSupport::TestCase
  test "14日以上経過した練習履歴が削除される" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )

    assert Practice.exists?(practice.id)

    Rails.application.load_tasks
    Rake::Task["practices:delete_expired"].reenable
    Rake::Task["practices:delete_expired"].invoke

    assert_not Practice.exists?(practice.id)
  end

  test "14日未満の練習履歴は削除されない" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 13.days.ago
    )

    assert Practice.exists?(practice.id)

    Rails.application.load_tasks
    Rake::Task["practices:delete_expired"].reenable
    Rake::Task["practices:delete_expired"].invoke

    assert Practice.exists?(practice.id)
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

    assert Practice.exists?(practice.id)
    assert Analysis.exists?(analysis.id)

    Rails.application.load_tasks
    Rake::Task["practices:delete_expired"].reenable
    Rake::Task["practices:delete_expired"].invoke

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

    Rails.application.load_tasks
    Rake::Task["practices:delete_expired"].reenable
    Rake::Task["practices:delete_expired"].invoke

    assert_not Practice.exists?(practice.id)
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
  end
end
