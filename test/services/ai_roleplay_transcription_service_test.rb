require "test_helper"

class AiRoleplayTranscriptionServiceTest < ActiveSupport::TestCase
  # Groq APIへの接続の代わりに、送信したリクエストを記録して指定のレスポンスを返す
  class FakeHttpClient
    attr_reader :host, :port, :use_ssl, :request

    def initialize(response)
      @response = response
    end

    def start(host, port, use_ssl:)
      @host = host
      @port = port
      @use_ssl = use_ssl

      yield self
    end

    def request(request = nil)
      return @request if request.nil?

      @request = request
      @response
    end
  end

  setup do
    @original_api_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-api-key"

    @audio_file = Tempfile.new([ "ai_roleplay_transcription_test", ".webm" ])
    @audio_file.binmode
    @audio_file.write("dummy audio data")
    @audio_file.flush
  end

  teardown do
    ENV["GROQ_API_KEY"] = @original_api_key
    @audio_file.close!
  end

  test "Groq APIへ音声を送信し、文字起こし結果のテキストを返す" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = { text: "いらっしゃいませ" }.to_json

    http_client = FakeHttpClient.new(response)

    result = AiRoleplayTranscriptionService.new(@audio_file, http_client: http_client).call

    assert_equal "いらっしゃいませ", result

    assert_equal "api.groq.com", http_client.host
    assert_equal 443, http_client.port
    assert_equal true, http_client.use_ssl

    request = http_client.request
    assert_instance_of Net::HTTP::Post, request
    assert_equal "/openai/v1/audio/transcriptions", request.path
    assert_equal "Bearer test-api-key", request["Authorization"]
    assert_includes request["Content-Type"], "multipart/form-data"

    body = request.body
    assert_includes body, "name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n"
    assert_includes body, "name=\"language\"\r\n\r\nja\r\n"
    assert_includes body, "name=\"file\"; filename=\"ai_roleplay_clerk_audio.webm\""
    assert_includes body, "Content-Type: audio/webm\r\n\r\ndummy audio data"
    refute_includes body, "guest"
  end

  test "Groq APIの呼び出しに失敗した場合は例外を送出する" do
    response = Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error")
    response.instance_variable_set(:@read, true)
    response.body = "error"

    error = assert_raises(RuntimeError) do
      AiRoleplayTranscriptionService.new(@audio_file, http_client: FakeHttpClient.new(response)).call
    end

    assert_includes error.message, "Groq API request failed: 500"
  end
end
