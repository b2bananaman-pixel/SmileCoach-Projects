require "test_helper"
require "rake"

class PracticesTaskTest < ActiveSupport::TestCase
  setup do
    # 毎回読み込むとタスクの処理が重複して登録され、1回のinvokeで複数回実行されるため、未定義の場合だけ読み込む
    Rails.application.load_tasks unless Rake::Task.task_defined?("practices:delete_expired")
    Rake::Task["practices:delete_expired"].reenable
    Rake::Task["practices:delete_expired_dry_run"].reenable
  end

  teardown do
    ENV.delete(AiRoleplayVideoRetentionService::ENABLED_ENV_KEY)
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

  test "AIロープレの録画削除が有効な場合は14日を過ぎた録画を削除し練習データの削除も行う" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )
    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    assert_output(/AIロープレの録画を1件削除しました（失敗: 0件）。/) do
      Rake::Task["practices:delete_expired"].invoke
    end

    assert_nil practice.reload.transcription
    assert AiRoleplaySession.exists?(session.id)
    assert_not session.reload.video.attached?
  end

  test "AIロープレの録画の削除に失敗した場合は非0の終了コードで終了する" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)
    error = nil

    stdout, = capture_io do
      session.video.blob.service.stub(:delete, ->(_key) { raise "storage unavailable" }) do
        error = assert_raises(SystemExit) do
          Rake::Task["practices:delete_expired"].invoke
        end
      end
    end

    assert_not error.success?
    assert_equal "AIロープレの録画の削除に1件失敗しました。", error.message
    assert_match(/AIロープレの録画を0件削除しました（失敗: 1件）。/, stdout)
    assert session.reload.video.attached?
  end

  test "AIロープレの録画の削除がすべて成功した場合は正常終了する" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    assert_nothing_raised do
      assert_output(/AIロープレの録画を1件削除しました（失敗: 0件）。/) do
        Rake::Task["practices:delete_expired"].invoke
      end
    end
  end

  test "AIロープレの録画削除が無効な場合は録画削除をスキップし練習データの削除は行う" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )
    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    AiRoleplayVideoRetentionService.stub(:delete_expired, -> { raise "録画削除を呼び出してはいけません" }) do
      assert_output(/AIロープレの録画削除は無効のためスキップしました/) do
        Rake::Task["practices:delete_expired"].invoke
      end
    end

    assert_nil practice.reload.transcription
    assert session.reload.video.attached?
  end

  test "dry-runは削除対象のAIロープレを表示するだけでデータを変更しない" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )
    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    assert_no_difference [ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
      assert_output(/削除対象のAIロープレ録画: 1件\n.*ai_roleplay_session_id: #{session.id}\n/) do
        Rake::Task["practices:delete_expired_dry_run"].invoke
      end
    end

    assert session.reload.video.attached?
    assert_equal "削除対象の文字起こしです", practice.reload.transcription
  end

  test "dry-runはAIロープレの録画削除が有効でもデータを変更しない" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    assert_no_difference [ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
      assert_output(/削除対象のAIロープレ録画: 1件/) do
        Rake::Task["practices:delete_expired_dry_run"].invoke
      end
    end

    assert session.reload.video.attached?
  end

  test "dry-runは削除対象がない場合に0件と表示する" do
    create_ai_roleplay_session_with_video(created_at: 13.days.ago)

    assert_output("[dry-run] 削除対象のAIロープレ録画: 0件\n") do
      Rake::Task["practices:delete_expired_dry_run"].invoke
    end
  end

  private

  def create_ai_roleplay_session_with_video(created_at:)
    session = AiRoleplaySession.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: created_at
    )
    session.video.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_volume.webm")),
      filename: "ai_roleplay.webm",
      content_type: "video/webm"
    )
    session
  end
end
