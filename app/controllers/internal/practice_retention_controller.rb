class Internal::PracticeRetentionController < ActionController::API
  before_action :authenticate!

  def destroy
    processed_count = PracticeRetentionService.delete_expired

    render json: {
      message: "#{processed_count}件の期限切れデータを削除しました。"
    }
  end

  private

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
