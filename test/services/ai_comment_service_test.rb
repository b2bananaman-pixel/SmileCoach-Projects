require "test_helper"
require_relative "../../app/services/ai_comment_service"

class AiCommentServiceTest < ActiveSupport::TestCase
  setup do
    @analysis = analyses(:one)
    @original_api_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-api-key"
  end

  teardown do
    ENV["GROQ_API_KEY"] = @original_api_key
  end

  test "分析結果をもとにAIコメントを取得できる" do
    response = Minitest::Mock.new
    response.expect(:is_a?, true, [ Net::HTTPSuccess ])
    response.expect(
      :body,
      {
        choices: [
          {
            message: {
              content: "フィラーを減らすため、一呼吸おいてから話す練習をしましょう。"
            }
          }
        ]
      }.to_json
    )

    http_client = Minitest::Mock.new
    http_client.expect(
      :start,
      response,
      [ String, Integer ],
      use_ssl: true
    )

    service = AiCommentService.new(@analysis, http_client: http_client)

    assert_equal(
      "フィラーを減らすため、一呼吸おいてから話す練習をしましょう。",
      service.call
    )

    response.verify
    http_client.verify
  end

  test "Groq APIがエラーを返した場合は例外になる" do
    response = Minitest::Mock.new
    response.expect(:is_a?, false, [ Net::HTTPSuccess ])
    response.expect(:code, "500")
    response.expect(:body, '{"error":"internal server error"}')

    http_client = Minitest::Mock.new
    http_client.expect(
      :start,
      response,
      [ String, Integer ],
      use_ssl: true
    )

    service = AiCommentService.new(@analysis, http_client: http_client)

    error = assert_raises(RuntimeError) do
      service.call
    end

    assert_includes error.message, "Groq API request failed"

    response.verify
    http_client.verify
  end
end
