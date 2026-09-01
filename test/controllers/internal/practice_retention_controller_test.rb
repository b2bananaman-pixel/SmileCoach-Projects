require "test_helper"

class Internal::PracticeRetentionControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = "test-retention-token"
    ENV["RETENTION_CLEANUP_TOKEN"] = @token
  end

  teardown do
    ENV.delete("RETENTION_CLEANUP_TOKEN")
  end

  test "正しいトークンなら削除処理を実行できる" do
    post internal_practice_retention_url,
         headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :success
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
end
