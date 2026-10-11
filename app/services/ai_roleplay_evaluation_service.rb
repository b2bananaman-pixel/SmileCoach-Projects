require "json"
require "net/http"
require "uri"

class AiRoleplayEvaluationService
  API_URL = "https://api.groq.com/openai/v1/chat/completions"
  MODEL = "openai/gpt-oss-20b"

  CATEGORIES = %w[
    hearing
    listening
    needs
    proposal
    closing
  ].freeze

  CATEGORY_KEYS = %w[
    score
    good_point
    improvement_point
  ].freeze

  SUMMARY_KEYS = %w[
    overall_strength
    priority_improvement
    next_practice_goal
  ].freeze

  SCORE_RANGE = (1..5).freeze

  SPEAKER_LABELS = {
    "user" => "店員",
    "assistant" => "お客様"
  }.freeze

  class InvalidResponseError < StandardError; end

  def initialize(ai_roleplay_session, http_client: Net::HTTP)
    @ai_roleplay_session = ai_roleplay_session
    @http_client = http_client
  end

  def call
    existing_evaluation = @ai_roleplay_session.ai_roleplay_evaluation
    return existing_evaluation if existing_evaluation.present?

    messages = @ai_roleplay_session.ai_roleplay_messages.order(:id).to_a
    return if messages.empty?

    api_key = ENV["GROQ_API_KEY"]
    raise "GROQ_API_KEY is not configured" if api_key.blank?

    uri = URI(API_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"

    request.body = {
      model: MODEL,
      messages: [
        {
          role: "system",
          content: system_prompt
        },
        {
          role: "user",
          content: user_prompt(messages)
        }
      ]
    }.to_json

    response = @http_client.start(
      uri.hostname,
      uri.port,
      use_ssl: true
    ) do |http|
      http.request(request)
    end

    # レスポンス本文には会話内容が含まれる可能性があるため、例外メッセージに含めない
    unless response.is_a?(Net::HTTPSuccess)
      raise "Groq API request failed: #{response.code}"
    end

    content = parse_json(response.body).dig(
      "choices",
      0,
      "message",
      "content"
    )

    raise "Groq API returned no response content" if content.blank?

    evaluation_attributes = validated_attributes(parse_json(content))

    @ai_roleplay_session.create_ai_roleplay_evaluation!(
      evaluation_attributes
    )
  end

  private

  def parse_json(json)
    JSON.parse(json)
  rescue JSON::ParserError
    raise InvalidResponseError, "Groq API returned invalid JSON"
  end

  def validated_attributes(result)
    unless result.is_a?(Hash)
      raise InvalidResponseError, "evaluation must be an object"
    end

    attributes = { reference_score: nil }

    CATEGORIES.each do |category|
      attributes.merge!(
        validated_category_attributes(category, result)
      )
    end

    SUMMARY_KEYS.each do |key|
      require_key!(result, key, key)
      require_text!(result[key], key)

      attributes[key.to_sym] = result[key]
    end

    attributes
  end

  def validated_category_attributes(category, result)
    require_key!(result, category, category)

    evaluation = result[category]

    unless evaluation.is_a?(Hash)
      raise InvalidResponseError, "#{category} must be an object"
    end

    CATEGORY_KEYS.each do |key|
      require_key!(evaluation, key, "#{category}.#{key}")
    end

    score = evaluation["score"]
    good_point = evaluation["good_point"]
    improvement_point = evaluation["improvement_point"]

    if score.nil?
      # 評価できない項目（N/A）は、スコア・良かった点・改善点をすべてnullとする
      unless good_point.nil? && improvement_point.nil?
        raise InvalidResponseError,
              "#{category} points must be null when score is null"
      end
    else
      unless score.is_a?(Integer) && SCORE_RANGE.cover?(score)
        raise InvalidResponseError,
              "#{category}.score must be an integer from 1 to 5 or null"
      end

      require_text!(good_point, "#{category}.good_point")
      require_text!(improvement_point, "#{category}.improvement_point")
    end

    {
      "#{category}_score": score,
      "#{category}_good_point": good_point,
      "#{category}_improvement_point": improvement_point
    }
  end

  def require_key!(hash, key, name)
    return if hash.key?(key)

    raise InvalidResponseError, "#{name} is missing"
  end

  def require_text!(value, name)
    return if value.is_a?(String) && value.present?

    raise InvalidResponseError, "#{name} must be a non-empty string"
  end

  def system_prompt
    <<~PROMPT
      あなたは接客ロールプレイの評価者です。
      店員とお客様の会話を読み、店員（練習者）の接客を評価してください。
      お客様の発言は評価対象ではありません。

      次の5項目を、それぞれ1〜5の整数で評価してください。

      hearing（ヒアリング）:
      お客様の現在の利用状況や背景を、質問によって適切に聞き出せているか。

      listening（傾聴）:
      お客様の発言を受け止め、共感や相づち、言い換えなどで理解を示せているか。

      needs（ニーズ把握）:
      お客様の要望や課題、本当に求めていることを把握できているか。

      proposal（提案）:
      把握したニーズに合った商品・サービスを、分かりやすく提案できているか。

      closing（クロージング）:
      お客様の意思を確認し、契約や次の行動へ自然に導けているか。

      スコアの基準:
      5: 非常に良い
      4: 良い
      3: 普通
      2: やや改善が必要
      1: 改善が必要

      会話が短い、または該当する場面がなく評価できない項目は、
      score、good_point、improvement_point をすべて null にしてください。

      評価できる項目では、good_point と improvement_point に、
      会話中の具体的な発言や場面に触れた日本語の文章を必ず設定してください。

      overall_strength には接客全体を通した強み、
      priority_improvement には最も優先して改善すべき点、
      next_practice_goal には次回の練習で意識する具体的な目標を、
      それぞれ日本語の文章で必ず設定してください。

      必ず以下の形式のJSONオブジェクトだけを返してください。
      Markdownやコードブロック、JSON以外の説明文は含めないでください。

      {
        "hearing": {
          "score": 1〜5の整数 または null,
          "good_point": "良かった点" または null,
          "improvement_point": "改善点" または null
        },
        "listening": { "score": ..., "good_point": ..., "improvement_point": ... },
        "needs": { "score": ..., "good_point": ..., "improvement_point": ... },
        "proposal": { "score": ..., "good_point": ..., "improvement_point": ... },
        "closing": { "score": ..., "good_point": ..., "improvement_point": ... },
        "overall_strength": "総合的な強み",
        "priority_improvement": "優先して改善すべき点",
        "next_practice_goal": "次回の練習目標"
      }
    PROMPT
  end

  def user_prompt(messages)
    practice_theme = @ai_roleplay_session.practice_theme

    <<~PROMPT
      練習テーマ: #{practice_theme.name}

      シナリオ:
      #{practice_theme.description}

      会話:
      #{transcript(messages)}

      上記の会話における店員の接客を評価し、指定されたJSON形式だけを返してください。
    PROMPT
  end

  def transcript(messages)
    messages.map do |message|
      "#{SPEAKER_LABELS.fetch(message.role)}: #{message.content}"
    end.join("\n")
  end
end
