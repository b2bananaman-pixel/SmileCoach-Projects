require "test_helper"

class AiRoleplayVideoRetentionServiceTest < ActiveSupport::TestCase
  VIDEO_FIXTURE = Rails.root.join("test/fixtures/files/test_volume.webm")

  test "14日を過ぎたAIロープレの録画を削除する" do
    session = create_session_with_video(created_at: 15.days.ago)
    attachment_id = session.video.attachment.id
    blob_id = session.video.blob.id

    result = AiRoleplayVideoRetentionService.delete_expired

    assert_equal 1, result.deleted_count
    assert_equal 0, result.failed_count
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not ActiveStorage::Blob.exists?(blob_id)
    assert_not session.reload.video.attached?
  end

  test "14日以内のAIロープレの録画は削除しない" do
    session = create_session_with_video(created_at: 13.days.ago)

    result = AiRoleplayVideoRetentionService.delete_expired

    assert_equal 0, result.deleted_count
    assert session.reload.video.attached?
  end

  test "録画を削除してもセッション・評価・会話・Practiceは残す" do
    session = ai_roleplay_sessions(:one)
    session.update!(created_at: 15.days.ago)
    attach_video(session)

    practice = Practice.create!(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session,
      transcription: "店員の発話です"
    )

    evaluation_id = session.ai_roleplay_evaluation.id
    message_ids = session.ai_roleplay_messages.ids

    AiRoleplayVideoRetentionService.delete_expired

    assert AiRoleplaySession.exists?(session.id)
    assert AiRoleplayEvaluation.exists?(evaluation_id)
    assert_equal message_ids.sort, AiRoleplayMessage.where(id: message_ids).ids.sort
    assert Practice.exists?(practice.id)
    assert_not session.reload.video.attached?
  end

  test "録画がないセッションは処理対象に含めない" do
    session = AiRoleplaySession.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )

    result = AiRoleplayVideoRetentionService.delete_expired

    assert_equal 0, result.deleted_count
    assert_equal 0, result.failed_count
    assert AiRoleplaySession.exists?(session.id)
    assert_not_includes AiRoleplayVideoRetentionService.expired_session_ids, session.id
  end

  test "再実行しても削除済みの録画は処理件数に含めない" do
    create_session_with_video(created_at: 15.days.ago)

    first_result = AiRoleplayVideoRetentionService.delete_expired
    second_result = AiRoleplayVideoRetentionService.delete_expired

    assert_equal 1, first_result.deleted_count
    assert_equal 0, second_result.deleted_count
    assert_equal 0, second_result.failed_count
  end

  test "1件の削除に失敗しても残りの録画を削除する" do
    failing_session = create_session_with_video(created_at: 16.days.ago)
    other_session = create_session_with_video(created_at: 15.days.ago)

    service = AiRoleplayVideoRetentionService.new
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    purge_video = lambda do |ai_roleplay_session|
      raise "storage-key-secret" if ai_roleplay_session.id == failing_session.id

      ai_roleplay_session.video.purge
    end

    result = service.stub(:purge_video, purge_video) do
      service.delete_expired
    end

    assert_equal 1, result.deleted_count
    assert_equal 1, result.failed_count
    assert failing_session.reload.video.attached?
    assert_not other_session.reload.video.attached?
    assert_includes log.string, "ai_roleplay_session_id=#{failing_session.id}"
    assert_includes log.string, "RuntimeError"
    assert_not_includes log.string, "storage-key-secret"
  ensure
    Rails.logger = original_logger
  end

  test "ストレージのファイル削除に失敗した場合は添付情報を残し次回の実行で削除する" do
    session = create_session_with_video(created_at: 15.days.ago)
    attachment_id = session.video.attachment.id
    blob = session.video.blob
    storage_service = blob.service

    failed_result = storage_service.stub(:delete, ->(_key) { raise "storage unavailable" }) do
      AiRoleplayVideoRetentionService.delete_expired
    end

    assert_equal 0, failed_result.deleted_count
    assert_equal 1, failed_result.failed_count
    assert ActiveStorage::Attachment.exists?(attachment_id)
    assert ActiveStorage::Blob.exists?(blob.id)
    assert storage_service.exist?(blob.key)
    assert_equal [ session.id ], AiRoleplayVideoRetentionService.expired_session_ids

    retried_result = AiRoleplayVideoRetentionService.delete_expired

    assert_equal 1, retried_result.deleted_count
    assert_equal 0, retried_result.failed_count
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not storage_service.exist?(blob.key)
  end

  test "ストレージのファイル削除に失敗した場合はストレージキーやURLをログに出さない" do
    session = create_session_with_video(created_at: 15.days.ago)
    blob = session.video.blob
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    blob.service.stub(:delete, ->(key) { raise "failed to delete #{key}" }) do
      AiRoleplayVideoRetentionService.delete_expired
    end

    assert_includes log.string, "ai_roleplay_session_id=#{session.id}"
    assert_not_includes log.string, blob.key
    assert_not_includes log.string, "failed to delete"
    assert_not_includes log.string, users(:one).email
  ensure
    Rails.logger = original_logger
  end

  test "ファイル削除後にDBの削除に失敗した場合も次回の実行で削除する" do
    session = create_session_with_video(created_at: 15.days.ago)
    attachment_id = session.video.attachment.id
    blob = session.video.blob

    service = AiRoleplayVideoRetentionService.new
    failed_result = service.stub(:purge_video_record, ->(_session) { raise ActiveRecord::StatementInvalid, "db unavailable" }) do
      service.delete_expired
    end

    assert_equal 1, failed_result.failed_count
    assert_not blob.service.exist?(blob.key)
    assert ActiveStorage::Attachment.exists?(attachment_id)
    assert ActiveStorage::Blob.exists?(blob.id)
    assert_equal [ session.id ], AiRoleplayVideoRetentionService.expired_session_ids

    # ファイルが既に削除されていても、再実行でDBの添付情報とblobを削除できる
    retried_result = AiRoleplayVideoRetentionService.delete_expired

    assert_equal 1, retried_result.deleted_count
    assert_equal 0, retried_result.failed_count
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not session.reload.video.attached?
  end

  test "他のレコードと共有しているblobはファイルを削除せず関連付けだけを外す" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one)
    )
    practice.video.attach(
      io: File.open(VIDEO_FIXTURE),
      filename: "practice_video.webm",
      content_type: "video/webm"
    )
    shared_blob = practice.video.blob

    session = AiRoleplaySession.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )
    session.video.attach(shared_blob)

    result = AiRoleplayVideoRetentionService.delete_expired

    assert_equal 1, result.deleted_count
    assert_equal 0, result.failed_count
    assert_not session.reload.video.attached?
    assert practice.reload.video.attached?
    assert ActiveStorage::Blob.exists?(shared_blob.id)
    assert shared_blob.service.exist?(shared_blob.key)
  end

  test "削除対象外のセッションや通常練習の添付ファイルは削除しない" do
    expired_session = create_session_with_video(created_at: 15.days.ago)
    recent_session = create_session_with_video(created_at: 13.days.ago)

    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )
    practice.audio.attach(
      io: File.open(VIDEO_FIXTURE),
      filename: "practice_audio.webm",
      content_type: "audio/webm"
    )

    recent_blob = recent_session.video.blob
    practice_blob = practice.audio.blob

    AiRoleplayVideoRetentionService.delete_expired

    assert_not expired_session.reload.video.attached?
    assert recent_session.reload.video.attached?
    assert recent_blob.service.exist?(recent_blob.key)
    assert practice.reload.audio.attached?
    assert practice_blob.service.exist?(practice_blob.key)
  end

  test "ストレージのファイルを削除してからDBの添付情報を削除する" do
    session = create_session_with_video(created_at: 15.days.ago)
    attachment_id = session.video.attachment.id
    storage_service = session.video.blob.service
    attachment_exists_on_file_delete = nil

    original_delete = storage_service.method(:delete)
    delete_file = lambda do |key|
      attachment_exists_on_file_delete = ActiveStorage::Attachment.exists?(attachment_id) if attachment_exists_on_file_delete.nil?
      original_delete.call(key)
    end

    storage_service.stub(:delete, delete_file) do
      AiRoleplayVideoRetentionService.delete_expired
    end

    assert_equal true, attachment_exists_on_file_delete
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
  end

  test "削除の有効化は環境変数が\"true\"の場合だけ" do
    with_enabled_env(nil) { assert_not AiRoleplayVideoRetentionService.enabled? }
    with_enabled_env("true") { assert AiRoleplayVideoRetentionService.enabled? }

    [ "false", "", "TRUE", "True", "1", "yes", " true" ].each do |value|
      with_enabled_env(value) do
        assert_not AiRoleplayVideoRetentionService.enabled?, "#{value.inspect}は無効として扱う"
      end
    end
  end

  test "削除対象のセッションIDだけを返しデータは変更しない" do
    expired_session = create_session_with_video(created_at: 15.days.ago)
    recent_session = create_session_with_video(created_at: 13.days.ago)

    assert_no_difference [ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count", "AiRoleplaySession.count" ] do
      assert_equal [ expired_session.id ], AiRoleplayVideoRetentionService.expired_session_ids
    end

    assert expired_session.reload.video.attached?
    assert recent_session.reload.video.attached?
  end

  test "環境変数で保持期間を12日に変更できる" do
    with_retention_days("12") do
      session = create_session_with_video(created_at: 13.days.ago)

      result = AiRoleplayVideoRetentionService.delete_expired

      assert_equal 1, result.deleted_count
      assert_not session.reload.video.attached?
    end
  end

  [ "abc", "0", "-1" ].each do |invalid_value|
    test "環境変数が不正な値（#{invalid_value}）の場合は14日にフォールバックする" do
      with_retention_days(invalid_value) do
        recent_session = create_session_with_video(created_at: 13.days.ago)
        expired_session = create_session_with_video(created_at: 15.days.ago)

        result = AiRoleplayVideoRetentionService.delete_expired

        assert_equal 1, result.deleted_count
        assert recent_session.reload.video.attached?
        assert_not expired_session.reload.video.attached?
      end
    end
  end

  test "通常練習の録画は削除しない" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: 15.days.ago
    )
    practice.video.attach(
      io: File.open(VIDEO_FIXTURE),
      filename: "practice_video.webm",
      content_type: "video/webm"
    )

    AiRoleplayVideoRetentionService.delete_expired

    assert practice.reload.video.attached?
  end

  private

  def create_session_with_video(created_at:)
    session = AiRoleplaySession.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: created_at
    )
    attach_video(session)
    session
  end

  def attach_video(session)
    session.video.attach(
      io: File.open(VIDEO_FIXTURE),
      filename: "ai_roleplay.webm",
      content_type: "video/webm"
    )
  end

  def with_enabled_env(value)
    key = AiRoleplayVideoRetentionService::ENABLED_ENV_KEY
    original_value = ENV[key]

    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end

    yield
  ensure
    if original_value.nil?
      ENV.delete(key)
    else
      ENV[key] = original_value
    end
  end

  def with_retention_days(value)
    original_value = ENV["PRACTICE_RETENTION_DAYS"]
    ENV["PRACTICE_RETENTION_DAYS"] = value

    yield
  ensure
    if original_value.nil?
      ENV.delete("PRACTICE_RETENTION_DAYS")
    else
      ENV["PRACTICE_RETENTION_DAYS"] = original_value
    end
  end
end
