require "json"
require "net/http"
require "uri"

class AiRoleplayEvaluationService
  API_URL = "https://api.groq.com/openai/v1/chat/completions"
  MODEL = "openai/gpt-oss-20b"

  # 推論トークンと評価JSONの出力が途中で切れないよう、出力上限を明示する
  MAX_COMPLETION_TOKENS = 8192

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

  FINISH_REASON_FORMAT = /\A[a-z_]{1,32}\z/

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
      max_completion_tokens: MAX_COMPLETION_TOKENS,
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

    choice = parse_json(response.body).dig("choices", 0)
    content = choice&.dig("message", "content")

    raise "Groq API returned no response content" if content.blank?

    evaluation_attributes = validated_attributes(
      parse_content(content, choice["finish_reason"])
    )

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

  # 出力の途中切れ（finish_reason: length）などを判別できるよう、finish_reasonを例外メッセージに含める
  def parse_content(content, finish_reason)
    JSON.parse(content)
  rescue JSON::ParserError
    raise InvalidResponseError,
          "Groq API returned invalid JSON " \
          "(finish_reason: #{safe_finish_reason(finish_reason)})"
  end

  # finish_reasonはAPIが返す短い識別子のみを出力し、想定外の値はunknownとする
  def safe_finish_reason(finish_reason)
    return finish_reason if finish_reason.is_a?(String) && finish_reason.match?(FINISH_REASON_FORMAT)

    "unknown"
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

      次の5項目それぞれについて、1〜5の整数で評価するか、評価対象外としてください。

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

      各項目は、次の「評価対象」か「評価対象外」のどちらか一方だけにしてください。
      1つの項目の中で、2つを混在させてはいけません。

      評価対象:
      その項目に当てはまる店員の発言や行動が会話中にある場合です。
      score を1〜5の整数にし、good_point と improvement_point の両方に、
      その発言や行動に触れた具体的な日本語の文章を必ず設定してください。
      score が1や2の低い評価でも、good_point と improvement_point は必ず文章にしてください。
      good_point には、会話中に実際にあった店員の発言や行動の中から、
      少しでもできていた点を書いてください。会話にない発言や行動を作り出してはいけません。

      評価対象外:
      その項目に当てはまる店員の発言や行動が会話中にない場合です。
      例えば、店員が契約の意思確認や次の行動の案内をしていなければ、closing は評価対象外です。
      score、good_point、improvement_point の3つをすべて null にしてください。

      score が数値の場合に、good_point や improvement_point を
      null、空文字、「なし」、「特になし」にしてはいけません。
      score が null の場合に、good_point や improvement_point に文章を入れてはいけません。
      評価対象外を表すために 0 を使ってはいけません。

      overall_strength には接客全体を通した強み、
      priority_improvement には最も優先して改善すべき点、
      next_practice_goal には次回の練習で意識する具体的な目標を、
      それぞれ日本語の文章で必ず設定してください。

      必ず以下の形式のJSONオブジェクトだけを返してください。
      Markdownやコードブロック、JSON以外の説明文は含めないでください。

      評価対象の項目の例:
      "hearing": { "score": 4, "good_point": "良かった点の文章", "improvement_point": "改善点の文章" }

      評価対象外の項目の例:
      "closing": { "score": null, "good_point": null, "improvement_point": null }

      返すJSONの形式:
      5項目と総合3項目のキーはすべて含めてください。
      各項目の値は、上の「評価対象の項目の例」か「評価対象外の項目の例」のどちらかの形にしてください。

      {
        "hearing": { "score": ..., "good_point": ..., "improvement_point": ... },
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
