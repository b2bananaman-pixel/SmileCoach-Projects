require "test_helper"
require_relative "../../app/services/ai_roleplay_response_service"

class AiRoleplayResponseServiceTest < ActiveSupport::TestCase
  setup do
    @original_api_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-api-key"
  end

  teardown do
    ENV["GROQ_API_KEY"] = @original_api_key
  end

  test "店員の発話をもとにAI顧客の構造化された返答を取得できる" do
    ai_response = {
      reply: "料金が少し気になっているんですが、今より安くなりますか？",
      customer_state: "interested",
      contract_intent: "considering",
      reason: "料金を比較したい",
      conversation_end: false,
      end_reason: nil
    }

    response = Minitest::Mock.new

    response.expect(:is_a?, true, [ Net::HTTPSuccess ])
    response.expect(
      :body,
      {
        choices: [
          {
            message: {
              content: ai_response.to_json
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

    service = AiRoleplayResponseService.new(
      clerk_message: "現在の料金プランについてお困りのことはありますか？",
      http_client: http_client
    )

    result = service.call

    assert_equal(
      "料金が少し気になっているんですが、今より安くなりますか？",
      result["reply"]
    )
    assert_equal "interested", result["customer_state"]
    assert_equal "considering", result["contract_intent"]
    assert_equal "料金を比較したい", result["reason"]
    assert_equal false, result["conversation_end"]
    assert_nil result["end_reason"]

    response.verify
    http_client.verify
  end

  test "店員の発話がGroq APIへのリクエストに含まれる" do
    response = Minitest::Mock.new

    response.expect(:is_a?, true, [ Net::HTTPSuccess ])
    response.expect(
      :body,
      {
        choices: [
          {
            message: {
              content: {
                reply: "今より安くなるなら詳しく聞きたいです。",
                customer_state: "interested",
                contract_intent: "considering",
                reason: "料金に関心がある",
                conversation_end: false,
                end_reason: nil
              }.to_json
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

        assert_includes(
          system_message["content"],
          "顧客役"
        )

        assert_includes(
          user_message["content"],
          "現在の料金プランについてお困りのことはありますか？"
        )
      end

      block.call(http)
      http.verify

      true
    end

    service = AiRoleplayResponseService.new(
      clerk_message: "現在の料金プランについてお困りのことはありますか？",
      http_client: http_client
    )

    result = service.call

    assert_equal(
      "今より安くなるなら詳しく聞きたいです。",
      result["reply"]
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

    service = AiRoleplayResponseService.new(
      clerk_message: "こんにちは。",
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

    service = AiRoleplayResponseService.new(
      clerk_message: "こんにちは。"
    )

    error = assert_raises(RuntimeError) do
      service.call
    end

    assert_equal(
      "GROQ_API_KEY is not configured",
      error.message
    )
  end

  test "店員の発話が空の場合は例外になる" do
    service = AiRoleplayResponseService.new(
      clerk_message: ""
    )

    error = assert_raises(ArgumentError) do
      service.call
    end

    assert_equal(
      "clerk_message is required",
      error.message
    )
  end
end
