require "test_helper"

class AiRoleplayVideoDeletionServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  VIDEO_FIXTURE = Rails.root.join("test/fixtures/files/test_volume.webm")

  setup do
    # テストではDisk（tmp/storage）に保存し、本番のGCSには接続しない
    assert_equal "test", ActiveStorage::Blob.service.name.to_s

    @session = ai_roleplay_sessions(:one)
    attach_video(@session)
  end

  test "録画の添付情報・blob・ストレージのファイルを削除する" do
    attachment_id = @session.video.attachment.id
    blob = @session.video.blob

    result = delete_video(@session)

    assert result.deleted?
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
    assert_not @session.video.attached?
    assert_not @session.reload.video.attached?
  end

  test "削除ジョブを登録せず、その場で削除する" do
    blob = @session.video.blob

    assert_no_enqueued_jobs do
      delete_video(@session)
    end

    assert_not blob.service.exist?(blob.key)
  end

  test "評価・会話・練習日時・Practice・Analysis・発話音声・文字起こしは残す" do
    practice = create_voice_analysis_practice(@session)
    audio_blob = practice.audio.blob
    evaluation = @session.ai_roleplay_evaluation
    message_attributes = @session.ai_roleplay_messages.order(:id).map(&:attributes)
    session_attributes = @session.reload.attributes.slice("user_id", "product_id", "product_snapshot", "duration",
                                                          "end_reason", "started_at", "ended_at", "created_at")
    analysis_attributes = practice.analysis.attributes

    delete_video(@session)

    assert_equal session_attributes, @session.reload.attributes.slice(*session_attributes.keys)
    assert_equal evaluation.attributes, AiRoleplayEvaluation.find(evaluation.id).attributes
    assert_equal message_attributes, @session.ai_roleplay_messages.order(:id).map(&:attributes)
    assert_not_empty message_attributes

    practice.reload
    assert_equal "店員の発話です", practice.transcription
    assert practice.audio.attached?
    assert audio_blob.service.exist?(audio_blob.key)
    assert_equal analysis_attributes, practice.analysis.attributes
  end

  test "他のセッションの録画や通常練習の添付ファイルは削除しない" do
    other_session = ai_roleplay_sessions(:two)
    attach_video(other_session)
    other_blob = other_session.video.blob

    practice = practices(:one)
    practice.video.attach(io: StringIO.new(File.binread(VIDEO_FIXTURE)), filename: "practice.webm", content_type: "video/webm")
    practice_blob = practice.video.blob

    delete_video(@session)

    assert other_session.reload.video.attached?
    assert other_blob.service.exist?(other_blob.key)
    assert practice.reload.video.attached?
    assert practice_blob.service.exist?(practice_blob.key)
  end

  test "ストレージのファイルを削除してからDBの添付情報を削除する" do
    attachment_id = @session.video.attachment.id
    storage_service = @session.video.blob.service
    attachment_exists_on_file_delete = nil

    original_delete = storage_service.method(:delete)
    delete_file = lambda do |key|
      attachment_exists_on_file_delete = ActiveStorage::Attachment.exists?(attachment_id) if attachment_exists_on_file_delete.nil?
      original_delete.call(key)
    end

    storage_service.stub(:delete, delete_file) do
      delete_video(@session)
    end

    assert_equal true, attachment_exists_on_file_delete
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
  end

  test "ストレージのファイル削除に失敗した場合は例外を送出し、添付情報とファイルを残す" do
    attachment_id = @session.video.attachment.id
    blob = @session.video.blob

    blob.service.stub(:delete, ->(_key) { raise "storage unavailable" }) do
      assert_raises(RuntimeError) { delete_video(@session) }
    end

    assert ActiveStorage::Attachment.exists?(attachment_id)
    assert ActiveStorage::Blob.exists?(blob.id)
    assert blob.service.exist?(blob.key)
    assert @session.reload.video.attached?

    # 再度削除できる
    assert delete_video(@session).deleted?
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
  end

  test "ファイルの削除後にDBの処理が失敗した場合は添付情報を残し、再度削除できる" do
    attachment_id = @session.video.attachment.id
    blob = @session.video.blob
    storage_service = blob.service

    original_delete = storage_service.method(:delete)
    delete_then_fail = lambda do |key|
      original_delete.call(key)
      raise ActiveRecord::StatementInvalid, "db unavailable"
    end

    storage_service.stub(:delete, delete_then_fail) do
      assert_raises(ActiveRecord::StatementInvalid) { delete_video(@session) }
    end

    assert_not storage_service.exist?(blob.key)
    assert ActiveStorage::Attachment.exists?(attachment_id)
    assert ActiveStorage::Blob.exists?(blob.id)

    # ファイルが既にない状態でも、DBの添付情報とblobを削除できる
    assert delete_video(@session).deleted?
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "他のレコードと共有しているblobはファイルを削除せず関連付けだけを外す" do
    shared_blob = @session.video.blob
    other_session = ai_roleplay_sessions(:two)
    other_session.video.attach(shared_blob)

    assert delete_video(@session).deleted?

    assert_not @session.reload.video.attached?
    assert other_session.reload.video.attached?
    assert ActiveStorage::Blob.exists?(shared_blob.id)
    assert shared_blob.service.exist?(shared_blob.key)
  end

  test "録画がないセッションは例外にせず削除済みとして扱う" do
    session = ai_roleplay_sessions(:two)

    assert_no_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ]) do
      assert delete_video(session).already_deleted?
    end
  end

  test "削除済みの録画をもう一度削除しても例外にならない" do
    assert delete_video(@session).deleted?

    assert_no_difference([ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ]) do
      assert delete_video(@session).already_deleted?
    end
  end

  test "読み込み済みのセッションの録画が自動削除で先に削除されていても、例外にせず削除済みとして扱う" do
    stale_session = AiRoleplaySession.with_attached_video.find(@session.id)
    assert stale_session.video.attached?

    @session.update_columns(created_at: 15.days.ago)
    AiRoleplayVideoRetentionService.delete_expired

    assert delete_video(stale_session).already_deleted?
    assert_not stale_session.video.attached?
  end

  test "自動削除が読み込んだ後に手動で削除しても、自動削除は失敗せず他のデータを削除しない" do
    @session.update_columns(created_at: 15.days.ago)
    practice = create_voice_analysis_practice(@session)
    audio_blob = practice.audio.blob
    stale_session = AiRoleplaySession.includes(video_attachment: :blob).find(@session.id)

    delete_video(@session)

    # 自動削除が先に読み込んだ古い状態のセッションで、録画の削除処理を続けた場合を再現する
    AiRoleplayVideoRetentionService.new.send(:purge_video, stale_session)

    assert AiRoleplaySession.exists?(@session.id)
    assert practice.reload.audio.attached?
    assert audio_blob.service.exist?(audio_blob.key)
    assert practice.analysis.present?
  end

  test "手動で削除した録画は14日間の自動削除の対象に含まれない" do
    @session.update_columns(created_at: 15.days.ago)
    assert_equal [ @session.id ], AiRoleplayVideoRetentionService.expired_session_ids

    delete_video(@session)

    assert_empty AiRoleplayVideoRetentionService.expired_session_ids
    result = AiRoleplayVideoRetentionService.delete_expired
    assert_equal 0, result.deleted_count
    assert_equal 0, result.failed_count
  end

  test "自動削除とロックの順番をそろえるため、添付情報の行だけをロックする" do
    locked_queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      locked_queries << payload[:sql] if payload[:sql].include?("FOR UPDATE")
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      delete_video(@session)
    end

    assert_equal 1, locked_queries.size
    assert_includes locked_queries.first, "active_storage_attachments"
    assert_not_includes locked_queries.first, "ai_roleplay_sessions"
  end

  private

  def delete_video(session)
    AiRoleplayVideoDeletionService.new(ai_roleplay_session: session).call
  end

  def attach_video(session)
    session.video.attach(
      io: StringIO.new(File.binread(VIDEO_FIXTURE)),
      filename: "ai_roleplay.webm",
      content_type: "video/webm"
    )
  end

  def create_voice_analysis_practice(session)
    practice = Practice.create!(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session,
      duration: 30.0,
      transcription: "店員の発話です"
    )
    practice.audio.attach(io: StringIO.new(File.binread(VIDEO_FIXTURE)), filename: "clerk_audio.webm", content_type: "audio/webm")
    practice.create_analysis!(total_score: 80, speech_speed: 7.0, filler_count: 1, volume: -20.0, ai_comment: "テスト用のコメントです。")
    practice
  end
end
