class Internal::PracticeRetentionController < ActionController::API
  before_action :authenticate!

  def destroy
    processed_count = PracticeRetentionService.delete_expired
    video_retention_result = ai_roleplay_video_retention_result

    # 録画の削除に1件でも失敗した場合は500を返し、GitHub Actions（curl --fail-with-body）で検知できるようにする
    status = video_retention_result.fetch(:ai_roleplay_video_failed_count, 0).positive? ? :internal_server_error : :ok

    render json: {
      message: "#{processed_count}件の期限切れデータを削除しました。",
      **video_retention_result
    }, status: status
  end

  # 削除対象の確認だけを行い、DB・ストレージのデータは変更しない
  def dry_run
    session_ids = AiRoleplayVideoRetentionService.expired_session_ids

    render json: {
      dry_run: true,
      ai_roleplay_video_retention_enabled: AiRoleplayVideoRetentionService.enabled?,
      ai_roleplay_video_expired_count: session_ids.size,
      ai_roleplay_session_ids: session_ids
    }
  end

  private

  # AIロープレの録画削除は環境変数で有効にした場合だけ実行する（通常練習の削除は常に実行する）
  def ai_roleplay_video_retention_result
    unless AiRoleplayVideoRetentionService.enabled?
      Rails.logger.info(
        "[Internal::PracticeRetentionController] AIロープレの録画削除は無効のためスキップしました"
      )

      return { ai_roleplay_video_retention_enabled: false }
    end

    video_result = AiRoleplayVideoRetentionService.delete_expired

    {
      ai_roleplay_video_retention_enabled: true,
      ai_roleplay_video_deleted_count: video_result.deleted_count,
      ai_roleplay_video_failed_count: video_result.failed_count
    }
  end

  def authenticate!
    expected_token = ENV["RETENTION_CLEANUP_TOKEN"]
    received_token = request.headers["Authorization"]&.delete_prefix("Bearer ")

    return if expected_token.present? && ActiveSupport::SecurityUtils.secure_compare(
      expected_token,
      received_token.to_s
    )

    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
