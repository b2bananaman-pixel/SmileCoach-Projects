require "test_helper"

class Internal::PracticeRetentionControllerTest < ActionDispatch::IntegrationTest
  VIDEO_FIXTURE = Rails.root.join("test/fixtures/files/test_volume.webm")

  setup do
    @token = "test-retention-token"
    ENV["RETENTION_CLEANUP_TOKEN"] = @token
  end

  teardown do
    ENV.delete("RETENTION_CLEANUP_TOKEN")
    ENV.delete(AiRoleplayVideoRetentionService::ENABLED_ENV_KEY)
  end

  test "正しいトークンなら削除処理を実行できる" do
    post internal_practice_retention_url,
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
  end

  test "AIロープレの録画削除が有効な場合は練習データとAIロープレの録画を削除し件数を返す" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    practice = create_expired_practice
    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    post internal_practice_retention_url,
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_equal(
      {
        "message" => "1件の期限切れデータを削除しました。",
        "ai_roleplay_video_retention_enabled" => true,
        "ai_roleplay_video_deleted_count" => 1,
        "ai_roleplay_video_failed_count" => 0
      },
      response.parsed_body
    )
    assert_response :ok
    assert_nil practice.reload.transcription
    assert AiRoleplaySession.exists?(session.id)
    assert_not session.reload.video.attached?
  end

  test "AIロープレの録画の削除に失敗した場合は500を返し成功件数と失敗件数を含める" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    practice = create_expired_practice
    failing_session = create_ai_roleplay_session_with_video(created_at: 16.days.ago)
    other_session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)
    failing_key = failing_session.video.blob.key
    storage_service = failing_session.video.blob.service
    original_delete = storage_service.method(:delete)

    delete_file = lambda do |key|
      raise "storage unavailable" if key == failing_key

      original_delete.call(key)
    end

    storage_service.stub(:delete, delete_file) do
      post internal_practice_retention_url,
           headers: { "Authorization" => "Bearer #{@token}" }
    end

    assert_response :internal_server_error
    assert_equal(
      {
        "message" => "1件の期限切れデータを削除しました。",
        "ai_roleplay_video_retention_enabled" => true,
        "ai_roleplay_video_deleted_count" => 1,
        "ai_roleplay_video_failed_count" => 1
      },
      response.parsed_body
    )
    assert_not_includes response.body, failing_key
    assert_nil practice.reload.transcription
    assert failing_session.reload.video.attached?
    assert_not other_session.reload.video.attached?
  end

  test "AIロープレの録画削除が有効で削除対象がない場合は200を返す" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    post internal_practice_retention_url,
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :ok
    assert_equal 0, response.parsed_body["ai_roleplay_video_deleted_count"]
    assert_equal 0, response.parsed_body["ai_roleplay_video_failed_count"]
  end

  test "AIロープレの録画削除が未設定の場合は練習データだけ削除し録画削除をスキップする" do
    practice = create_expired_practice
    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    AiRoleplayVideoRetentionService.stub(:delete_expired, -> { raise "録画削除を呼び出してはいけません" }) do
      post internal_practice_retention_url,
           headers: { "Authorization" => "Bearer #{@token}" }
    end

    assert_response :ok
    assert_equal(
      {
        "message" => "1件の期限切れデータを削除しました。",
        "ai_roleplay_video_retention_enabled" => false
      },
      response.parsed_body
    )
    assert_includes log.string, "AIロープレの録画削除は無効のためスキップしました"
    assert_nil practice.reload.transcription
    assert session.reload.video.attached?
  ensure
    Rails.logger = original_logger
  end

  [ "false", "", "TRUE", "1", "yes" ].each do |value|
    test "AIロープレの録画削除の設定値が#{value.inspect}の場合は録画を削除しない" do
      ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = value

      session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

      post internal_practice_retention_url,
           headers: { "Authorization" => "Bearer #{@token}" }

      assert_response :success
      assert_equal false, response.parsed_body["ai_roleplay_video_retention_enabled"]
      assert session.reload.video.attached?
    end
  end

  test "認証に失敗した場合はAIロープレの録画を削除しない" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    post internal_practice_retention_url,
         headers: { "Authorization" => "Bearer wrong-token" }

    assert_response :unauthorized
    assert session.reload.video.attached?
  end

  test "間違ったトークンでは実行できない" do
    post internal_practice_retention_url,
         headers: { "Authorization" => "Bearer wrong-token" }

    assert_response :unauthorized
  end

  test "トークンがない場合は実行できない" do
    post internal_practice_retention_url

    assert_response :unauthorized
  end

  test "dry-runは削除対象のAIロープレの件数とセッションIDだけを返しデータを変更しない" do
    ENV[AiRoleplayVideoRetentionService::ENABLED_ENV_KEY] = "true"

    practice = create_expired_practice
    expired_session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)
    create_ai_roleplay_session_with_video(created_at: 13.days.ago)

    AiRoleplayVideoRetentionService.stub(:delete_expired, -> { raise "dry-runで削除してはいけません" }) do
      PracticeRetentionService.stub(:delete_expired, -> { raise "dry-runで削除してはいけません" }) do
        assert_no_difference [ "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
          get internal_practice_retention_dry_run_url,
              headers: { "Authorization" => "Bearer #{@token}" }
        end
      end
    end

    assert_response :success
    assert_equal(
      {
        "dry_run" => true,
        "ai_roleplay_video_retention_enabled" => true,
        "ai_roleplay_video_expired_count" => 1,
        "ai_roleplay_session_ids" => [ expired_session.id ]
      },
      response.parsed_body
    )
    assert_not_includes response.body, users(:one).email
    assert_not_includes response.body, expired_session.video.blob.key
    assert_not_includes response.body, "/rails/active_storage/"
    assert expired_session.reload.video.attached?
    assert_equal "削除対象の文字起こしです", practice.reload.transcription
  end

  test "dry-runはAIロープレの録画削除が無効でも実行できる" do
    expired_session = create_ai_roleplay_session_with_video(created_at: 15.days.ago)

    get internal_practice_retention_dry_run_url,
        headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
    assert_equal false, response.parsed_body["ai_roleplay_video_retention_enabled"]
    assert_equal 1, response.parsed_body["ai_roleplay_video_expired_count"]
    assert_equal [ expired_session.id ], response.parsed_body["ai_roleplay_session_ids"]
    assert expired_session.reload.video.attached?
  end

  test "dry-runは間違ったトークンでは401を返す" do
    get internal_practice_retention_dry_run_url,
        headers: { "Authorization" => "Bearer wrong-token" }

    assert_response :unauthorized
    assert_not response.parsed_body.key?("ai_roleplay_session_ids")
  end

  test "dry-runはトークンがない場合は401を返す" do
    get internal_practice_retention_dry_run_url

    assert_response :unauthorized
  end

  private

  def create_expired_practice
    Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      transcription: "削除対象の文字起こしです",
      created_at: 15.days.ago
    )
  end

  def create_ai_roleplay_session_with_video(created_at:)
    session = AiRoleplaySession.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      created_at: created_at
    )
    session.video.attach(
      io: File.open(VIDEO_FIXTURE),
      filename: "ai_roleplay.webm",
      content_type: "video/webm"
    )
    session
  end
end
