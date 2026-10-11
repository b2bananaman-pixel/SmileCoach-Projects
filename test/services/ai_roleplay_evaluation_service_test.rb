require "test_helper"

class AiRoleplayEvaluationServiceTest < ActiveSupport::TestCase
  class FakeHttpClient
    attr_reader :requests, :start_args

    def initialize(response)
      @response = response
      @requests = []
    end

    def start(host, port, use_ssl:)
      @start_args = { host: host, port: port, use_ssl: use_ssl }

      yield self
    end

    def request(request)
      @requests << request
      @response
    end

    def called?
      @requests.any?
    end
  end

  setup do
    @original_api_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-api-key"

    @session = AiRoleplaySession.create!(
      user: users(:one),
      practice_theme: practice_themes(:one)
    )

    @session.ai_roleplay_messages.create!(
      role: "user",
      content: "いらっしゃいませ。冷蔵庫をお探しですか？"
    )
    @session.ai_roleplay_messages.create!(
      role: "assistant",
      content: "はい、今の冷蔵庫が古くなってきて。"
    )
    @session.ai_roleplay_messages.create!(
      role: "user",
      content: "何人家族でお使いですか？"
    )
  end

  teardown do
    ENV["GROQ_API_KEY"] = @original_api_key
  end

  test "Groq APIの評価結果を保存できる" do
    http_client = FakeHttpClient.new(
      successful_response(valid_evaluation)
    )

    evaluation = nil

    assert_difference("AiRoleplayEvaluation.count", 1) do
      evaluation = build_service(http_client).call
    end

    assert_equal @session, evaluation.ai_roleplay_session
    assert_equal 4, evaluation.hearing_score
    assert_equal "家族構成を質問できていました。", evaluation.hearing_good_point
    assert_equal "利用年数も確認しましょう。", evaluation.hearing_improvement_point
    assert_equal 3, evaluation.listening_score
    assert_equal 3, evaluation.needs_score
    assert_equal 2, evaluation.proposal_score
    assert_equal 1, evaluation.closing_score
    assert_equal "明るく声掛けできていました。", evaluation.overall_strength
    assert_equal "提案につなげる質問を増やしましょう。", evaluation.priority_improvement
    assert_equal "利用状況を3つ以上確認する。", evaluation.next_practice_goal
    assert_nil evaluation.reference_score
  end

  test "評価できない項目はスコア・良かった点・改善点をnullで保存できる" do
    result = valid_evaluation
    result["closing"] = not_applicable

    http_client = FakeHttpClient.new(successful_response(result))

    evaluation = build_service(http_client).call

    assert_nil evaluation.closing_score
    assert_nil evaluation.closing_good_point
    assert_nil evaluation.closing_improvement_point
    assert_equal 4, evaluation.hearing_score
  end

  test "AIがreference_scoreを返してもnullで保存する" do
    result = valid_evaluation
    result["reference_score"] = 80

    http_client = FakeHttpClient.new(successful_response(result))

    evaluation = build_service(http_client).call

    assert_nil evaluation.reference_score
  end

  test "練習テーマと発言順どおりの会話をGroq APIへ送信する" do
    http_client = FakeHttpClient.new(
      successful_response(valid_evaluation)
    )

    build_service(http_client).call

    assert_equal(
      { host: "api.groq.com", port: 443, use_ssl: true },
      http_client.start_args
    )
    assert_equal 1, http_client.requests.length

    request = http_client.requests.first

    assert_equal "Bearer test-api-key", request["Authorization"]
    assert_equal "application/json", request["Content-Type"]

    body = JSON.parse(request.body)

    assert_equal "openai/gpt-oss-20b", body["model"]

    messages = body["messages"]

    assert_equal %w[system user], messages.pluck("role")
    assert_includes messages[0]["content"], "評価者"

    user_content = messages[1]["content"]

    assert_includes user_content, practice_themes(:one).name
    assert_includes user_content, practice_themes(:one).description
    assert_includes(
      user_content,
      [
        "店員: いらっしゃいませ。冷蔵庫をお探しですか？",
        "お客様: はい、今の冷蔵庫が古くなってきて。",
        "店員: 何人家族でお使いですか？"
      ].join("\n")
    )
  end

  test "会話履歴が0件の場合はGroq APIを呼ばず評価を作成しない" do
    @session.ai_roleplay_messages.destroy_all

    http_client = FakeHttpClient.new(
      successful_response(valid_evaluation)
    )

    assert_no_difference("AiRoleplayEvaluation.count") do
      assert_nil build_service(http_client).call
    end

    assert_not http_client.called?
  end

  test "評価結果が既に存在する場合はGroq APIを呼ばず既存結果を維持する" do
    existing_evaluation = ai_roleplay_evaluations(:one)
    session = existing_evaluation.ai_roleplay_session

    http_client = FakeHttpClient.new(
      successful_response(valid_evaluation)
    )

    result = nil

    assert_no_difference("AiRoleplayEvaluation.count") do
      result = AiRoleplayEvaluationService.new(
        session,
        http_client: http_client
      ).call
    end

    assert_equal existing_evaluation, result
    assert_not http_client.called?
    assert_equal 1, existing_evaluation.reload.hearing_score
    assert_equal "MyText", existing_evaluation.hearing_good_point
  end

  test "Groq APIがエラーを返した場合はレスポンス本文を含まない例外になる" do
    response = Net::HTTPInternalServerError.new(
      "1.1",
      "500",
      "Internal Server Error"
    )
    set_response_body(response, '{"error":"secret detail"}')

    http_client = FakeHttpClient.new(response)

    assert_no_difference("AiRoleplayEvaluation.count") do
      error = assert_raises(RuntimeError) do
        build_service(http_client).call
      end

      assert_equal "Groq API request failed: 500", error.message
      assert_not_includes error.message, "secret detail"
    end
  end

  test "APIキーが設定されていない場合は例外になる" do
    ENV["GROQ_API_KEY"] = nil

    http_client = FakeHttpClient.new(
      successful_response(valid_evaluation)
    )

    assert_no_difference("AiRoleplayEvaluation.count") do
      error = assert_raises(RuntimeError) do
        build_service(http_client).call
      end

      assert_equal "GROQ_API_KEY is not configured", error.message
    end

    assert_not http_client.called?
  end

  test "レスポンス内容が空の場合は例外になる" do
    http_client = FakeHttpClient.new(successful_response(""))

    assert_no_difference("AiRoleplayEvaluation.count") do
      error = assert_raises(RuntimeError) do
        build_service(http_client).call
      end

      assert_equal "Groq API returned no response content", error.message
    end
  end

  test "レスポンス内容がJSONではない場合は例外になる" do
    http_client = FakeHttpClient.new(
      successful_response("評価結果です")
    )

    assert_invalid_response(http_client)
  end

  test "レスポンス内容がJSONオブジェクトではない場合は例外になる" do
    http_client = FakeHttpClient.new(successful_response([]))

    assert_invalid_response(http_client)
  end

  test "評価項目のキーが不足している場合は例外になる" do
    AiRoleplayEvaluationService::CATEGORIES.each do |category|
      result = valid_evaluation
      result.delete(category)

      assert_invalid_response(
        FakeHttpClient.new(successful_response(result)),
        "#{category} is missing"
      )
    end
  end

  test "評価項目がオブジェクトではない場合は例外になる" do
    result = valid_evaluation
    result["hearing"] = 4

    assert_invalid_response(
      FakeHttpClient.new(successful_response(result))
    )
  end

  test "評価項目内のキーが不足している場合は例外になる" do
    AiRoleplayEvaluationService::CATEGORY_KEYS.each do |key|
      result = valid_evaluation
      result["hearing"].delete(key)

      assert_invalid_response(
        FakeHttpClient.new(successful_response(result)),
        "hearing.#{key} is missing"
      )
    end
  end

  test "N/A項目のキーが不足している場合は例外になる" do
    AiRoleplayEvaluationService::CATEGORY_KEYS.each do |key|
      result = valid_evaluation
      result["closing"] = not_applicable
      result["closing"].delete(key)

      assert_invalid_response(
        FakeHttpClient.new(successful_response(result)),
        "closing.#{key} is missing"
      )
    end
  end

  test "N/A項目に良かった点や改善点がある場合は例外になる" do
    %w[good_point improvement_point].each do |key|
      result = valid_evaluation
      result["closing"] = not_applicable
      result["closing"][key] = "コメントです。"

      assert_invalid_response(
        FakeHttpClient.new(successful_response(result))
      )
    end
  end

  test "総合評価のキーが不足している場合は例外になる" do
    AiRoleplayEvaluationService::SUMMARY_KEYS.each do |key|
      result = valid_evaluation
      result.delete(key)

      assert_invalid_response(
        FakeHttpClient.new(successful_response(result)),
        "#{key} is missing"
      )
    end
  end

  test "スコアが1から5の範囲外の場合は補正せず例外になる" do
    [ 0, 6, -1 ].each do |score|
      result = valid_evaluation
      result["hearing"]["score"] = score

      assert_invalid_response(
        FakeHttpClient.new(successful_response(result))
      )
    end
  end

  test "スコアが整数ではない場合は例外になる" do
    [ "3", 3.5, 3.0, true ].each do |score|
      result = valid_evaluation
      result["hearing"]["score"] = score

      assert_invalid_response(
        FakeHttpClient.new(successful_response(result))
      )
    end
  end

  test "スコアがある項目の良かった点や改善点が空の場合は例外になる" do
    %w[good_point improvement_point].each do |key|
      [ nil, "", "  ", 1 ].each do |value|
        result = valid_evaluation
        result["hearing"][key] = value

        assert_invalid_response(
          FakeHttpClient.new(successful_response(result))
        )
      end
    end
  end

  test "総合評価が空や文字列以外の場合は例外になる" do
    AiRoleplayEvaluationService::SUMMARY_KEYS.each do |key|
      [ nil, "", 1 ].each do |value|
        result = valid_evaluation
        result[key] = value

        assert_invalid_response(
          FakeHttpClient.new(successful_response(result))
        )
      end
    end
  end

  private

  def build_service(http_client)
    AiRoleplayEvaluationService.new(
      @session,
      http_client: http_client
    )
  end

  def assert_invalid_response(http_client, message = nil)
    assert_no_difference("AiRoleplayEvaluation.count") do
      error = assert_raises(
        AiRoleplayEvaluationService::InvalidResponseError
      ) do
        build_service(http_client).call
      end

      assert_equal message, error.message if message
    end
  end

  def valid_evaluation
    {
      "hearing" => {
        "score" => 4,
        "good_point" => "家族構成を質問できていました。",
        "improvement_point" => "利用年数も確認しましょう。"
      },
      "listening" => {
        "score" => 3,
        "good_point" => "お客様の発言を受け止めていました。",
        "improvement_point" => "共感の言葉を加えましょう。"
      },
      "needs" => {
        "score" => 3,
        "good_point" => "買い替え理由を把握できていました。",
        "improvement_point" => "重視する点を確認しましょう。"
      },
      "proposal" => {
        "score" => 2,
        "good_point" => "商品の特徴を説明できていました。",
        "improvement_point" => "ニーズと結び付けて提案しましょう。"
      },
      "closing" => {
        "score" => 1,
        "good_point" => "最後まで丁寧に対応できていました。",
        "improvement_point" => "購入意思を確認しましょう。"
      },
      "overall_strength" => "明るく声掛けできていました。",
      "priority_improvement" => "提案につなげる質問を増やしましょう。",
      "next_practice_goal" => "利用状況を3つ以上確認する。"
    }
  end

  def not_applicable
    {
      "score" => nil,
      "good_point" => nil,
      "improvement_point" => nil
    }
  end

  def successful_response(content)
    content = content.to_json unless content.is_a?(String)

    response = Net::HTTPOK.new("1.1", "200", "OK")

    set_response_body(
      response,
      {
        choices: [
          {
            message: {
              content: content
            }
          }
        ]
      }.to_json
    )

    response
  end

  def set_response_body(response, body)
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
  end
end
