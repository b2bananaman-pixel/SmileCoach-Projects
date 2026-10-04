require "json"
require "net/http"
require "uri"

class AiRoleplayResponseService
  API_URL = "https://api.groq.com/openai/v1/chat/completions"
  MODEL = "openai/gpt-oss-20b"

  CUSTOMER_STATES = %w[
    neutral
    interested
    convinced
    confused
    troubled
    dissatisfied
    surprised
    purchased
  ].freeze

  def initialize(
    clerk_message:,
    conversation_history: [],
    http_client: Net::HTTP
  )
    @clerk_message = clerk_message
    @conversation_history = conversation_history
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
      messages: messages
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

    parsed_content = JSON.parse(content)
    normalize_customer_state(parsed_content)
  end

  private

  def messages
    [
      {
        role: "system",
        content: system_prompt
      },
      *conversation_messages,
      {
        role: "user",
        content: user_prompt
      }
    ]
  end

  def conversation_messages
    return [] unless @conversation_history.is_a?(Array)

    @conversation_history.filter_map do |message|
      normalized_message(message)
    end
  end

  def normalized_message(message)
    return unless message.respond_to?(:to_h)

    message = message.to_h

    role =
      message["role"] ||
      message[:role]

    content =
      message["content"] ||
      message[:content]

    return unless %w[user assistant].include?(role.to_s)
    return if content.blank?

    {
      role: role.to_s,
      content: content.to_s
    }
  end

  def normalize_customer_state(response)
    customer_state = response["customer_state"].to_s

    unless CUSTOMER_STATES.include?(customer_state)
      response["customer_state"] = "neutral"
    end

    response
  end

  def system_prompt
    <<~PROMPT
      あなたは接客ロールプレイの顧客役です。
      店員の発話に対して、実際の顧客として自然な日本語で返答してください。

      今回は携帯電話ショップで料金プランや乗り換えを検討している顧客を演じてください。
      一度の返答は長くなりすぎないよう、会話として自然な1〜2文程度にしてください。

      これまでの会話履歴がある場合は、その内容と矛盾しないように会話を続けてください。
      以前に話した家族構成、利用状況、希望、懸念などを必要に応じて引き継いでください。

      顧客の状態 customer_state は、会話内容に応じて必ず次の8種類から最も適切なものを1つ選んでください。

      neutral:
      通常の状態です。まだ大きな感情変化や判断の変化がありません。

      interested:
      商品、サービス、料金プラン、提案などに興味を持っている状態です。

      convinced:
      店員の説明を理解し、内容に納得している状態です。

      confused:
      店員の説明や提案内容を十分に理解できておらず、疑問が残っている状態です。

      troubled:
      選択や判断に迷っている、またはどうすればよいか困っている状態です。

      dissatisfied:
      提案内容、料金、条件、店員の対応などに不満を感じている状態です。

      surprised:
      料金、条件、メリット、説明内容などに驚いている状態です。
      驚きは肯定的な場合と否定的な場合のどちらでも使用できます。

      purchased:
      商品やサービスの購入、申し込み、契約を明確に決定した状態です。
      単に興味を持った、前向きに検討している、納得しただけの場合には使用しないでください。
      顧客が「それでお願いします」「契約します」など、購入・契約する意思を明確に示した場合に使用してください。

      customer_stateは段階を順番に進める必要はありません。
      実際の会話内容に応じて状態を選択し、以前の状態から良くなる場合も悪くなる場合もあります。

      purchasedを選択した場合は、
      contract_intentをpositive、
      conversation_endをtrue、
      end_reasonをcontract
      としてください。

      必ず以下の6項目を持つJSONオブジェクトだけを返してください。
      Markdownやコードブロック、JSON以外の説明文は含めないでください。

      {
        "reply": "顧客として実際に発話する文章",
        "customer_state": "neutral または interested または convinced または confused または troubled または dissatisfied または surprised または purchased",
        "contract_intent": "none または considering または positive または negative",
        "reason": "現在の顧客状態や契約意向になった理由",
        "conversation_end": false,
        "end_reason": null
      }

      reply:
      店員に対する顧客の自然な返答です。

      customer_state:
      顧客の現在の感情、理解、反応、購入決定状態を表します。
      必ず指定された8種類のいずれかを使用してください。

      contract_intent:
      現在の契約意向を表します。

      reason:
      customer_state と contract_intent を判断した理由を簡潔に表します。

      conversation_end:
      会話を終了すべき場合のみ true にしてください。
      通常は false にしてください。
      purchasedの場合はtrueにしてください。

      end_reason:
      conversation_end が true の場合は終了理由を文字列で設定してください。
      purchasedの場合はcontractにしてください。
      conversation_endがfalseの場合はnullにしてください。
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      店員から次のように話しかけられました。

      #{@clerk_message}

      これまでの会話内容を踏まえて、
      顧客役として自然に返答し、指定されたJSON形式だけを返してください。
    PROMPT
  end
end
