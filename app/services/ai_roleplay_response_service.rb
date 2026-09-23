require "json"
require "net/http"
require "uri"

class AiRoleplayResponseService
  API_URL = "https://api.groq.com/openai/v1/chat/completions"
  MODEL = "openai/gpt-oss-20b"

  def initialize(clerk_message:, http_client: Net::HTTP)
    @clerk_message = clerk_message
    @http_client = http_client
  end

  def call
    raise ArgumentError, "clerk_message is required" if @clerk_message.blank?

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
          content: user_prompt
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

    unless response.is_a?(Net::HTTPSuccess)
      raise "Groq API request failed: #{response.code} #{response.body}"
    end

    result = JSON.parse(response.body)
    content = result.dig(
      "choices",
      0,
      "message",
      "content"
    )

    raise "Groq API returned no response content" if content.blank?

    JSON.parse(content)
  end

  private

  def system_prompt
    <<~PROMPT
      あなたは接客ロールプレイの顧客役です。
      店員の発話に対して、実際の顧客として自然な日本語で返答してください。

      今回は携帯電話ショップで料金プランや乗り換えを検討している顧客を演じてください。
      一度の返答は長くなりすぎないよう、会話として自然な1〜2文程度にしてください。

      必ず以下の6項目を持つJSONオブジェクトだけを返してください。
      Markdownやコードブロック、JSON以外の説明文は含めないでください。

      {
        "reply": "顧客として実際に発話する文章",
        "customer_state": "neutral または interested または concerned または satisfied",
        "contract_intent": "none または considering または positive または negative",
        "reason": "現在の顧客状態や契約意向になった理由",
        "conversation_end": false,
        "end_reason": null
      }

      reply:
      店員に対する顧客の自然な返答です。

      customer_state:
      顧客の現在の感情・状態を表します。

      contract_intent:
      現在の契約意向を表します。

      reason:
      customer_state と contract_intent を判断した理由を簡潔に表します。

      conversation_end:
      会話を終了すべき場合のみ true にしてください。
      通常は false にしてください。

      end_reason:
      conversation_end が true の場合は終了理由を文字列で設定してください。
      false の場合は null にしてください。
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      店員から次のように話しかけられました。

      #{@clerk_message}

      顧客役として自然に返答し、指定されたJSON形式だけを返してください。
    PROMPT
  end
end
