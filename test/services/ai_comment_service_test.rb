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

    service = AiCommentService.new(
      @analysis,
      http_client: http_client
    )

    assert_equal(
      "フィラーを減らすため、一呼吸おいてから話す練習をしましょう。",
      service.call
    )

    response.verify
    http_client.verify
  end

  test "分析結果がGroq APIへのリクエストに含まれる" do
    response = Minitest::Mock.new

    response.expect(:is_a?, true, [ Net::HTTPSuccess ])
    response.expect(
      :body,
      {
        choices: [
          {
            message: {
              content: "テスト用のAIコメントです。"
            }
          }
        ]
      }.to_json
    )

    http_client = Minitest::Mock.new

    http_client.expect(
      :start,
      response
    ) do |host, port, use_ssl:, &block|
      assert_equal "api.groq.com", host
      assert_equal 443, port
      assert_equal true, use_ssl

      http = Minitest::Mock.new

      http.expect(:request, response) do |request|
        assert_equal "Bearer test-api-key", request["Authorization"]
        assert_equal "application/json", request["Content-Type"]

        body = JSON.parse(request.body)

        assert_equal "openai/gpt-oss-20b", body["model"]

        messages = body["messages"]

        assert_equal 2, messages.length

        system_message = messages.find do |message|
          message["role"] == "system"
        end

        user_message = messages.find do |message|
          message["role"] == "user"
        end

        assert_not_nil system_message
        assert_not_nil user_message

        user_content = user_message["content"]

        assert_includes(
          user_content,
          "総合スコア: #{@analysis.total_score}点"
        )

        assert_includes(
          user_content,
          "話速スコア: #{@analysis.speech_speed_score}点"
        )

        assert_includes(
          user_content,
          "フィラースコア: #{@analysis.filler_score}点"
        )

        assert_includes(
          user_content,
          "声量スコア: #{@analysis.volume_score}点"
        )

        assert_includes(
          user_content,
          "話速: #{@analysis.speech_speed}文字/秒"
        )

        assert_includes(
          user_content,
          "フィラー回数: #{@analysis.filler_count}回"
        )

        assert_includes(
          user_content,
          "声量: #{@analysis.volume}dB"
        )
      end

      block.call(http)
      http.verify

      true
    end

    service = AiCommentService.new(
      @analysis,
      http_client: http_client
    )

    assert_equal(
      "テスト用のAIコメントです。",
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

    service = AiCommentService.new(
      @analysis,
      http_client: http_client
    )

    error = assert_raises(RuntimeError) do
      service.call
    end

    assert_includes(
      error.message,
      "Groq API request failed"
    )

    response.verify
    http_client.verify
  end

  test "APIキーが設定されていない場合は例外になる" do
    ENV["GROQ_API_KEY"] = nil

    service = AiCommentService.new(
      @analysis
    )

    error = assert_raises(RuntimeError) do
      service.call
    end

    assert_equal(
      "GROQ_API_KEY is not configured",
      error.message
    )
  end
end
