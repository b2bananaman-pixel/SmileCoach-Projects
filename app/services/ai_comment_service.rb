require "net/http"
require "uri"
require "json"

class AICommentService
  API_URL = "https://api.groq.com/openai/v1/chat/completions"
  MODEL = "openai/gpt-oss-20b"

  def initialize(analysis, http_client: Net::HTTP)
    @analysis = analysis
    @http_client = http_client
  end

  def call
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
    result.dig("choices", 0, "message", "content")
  end

  private

  def system_prompt
    <<~PROMPT
      あなたは接客練習をサポートするコーチです。
      ユーザーを否定せず、前向きで具体的な改善アドバイスを日本語で簡潔に伝えてください。
      スコアが低い項目を優先して改善ポイントを伝えてください。
      実行しやすい具体的なアドバイスを含めてください。
      コメントは1〜2文程度にしてください。
    PROMPT
  end

  def user_prompt
    <<~PROMPT
      以下は接客練習の分析結果です。

      総合スコア: #{@analysis.total_score}点
      話速スコア: #{@analysis.speech_speed_score}点
      フィラースコア: #{@analysis.filler_score}点
      声量スコア: #{@analysis.volume_score}点

      話速: #{@analysis.speech_speed}文字/秒
      フィラー回数: #{@analysis.filler_count}回
      声量: #{@analysis.volume}dB

      上記の分析結果をもとに、次回の練習で改善できるポイントを日本語で1〜2文で伝えてください。
    PROMPT
  end
end
