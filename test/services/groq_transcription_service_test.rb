require "test_helper"
require "stringio"
require "ostruct"

class GroqTranscriptionServiceTest < ActiveSupport::TestCase
  test "文字起こし結果を取得できる" do
    response_body = {
      text: "こんにちは。本日はよろしくお願いいたします。"
    }.to_json

    result = JSON.parse(response_body)

    assert_equal(
      "こんにちは。本日はよろしくお願いいたします。",
      result["text"]
    )
  end

  test "Groq APIに正しいファイル情報を送信できる" do
    audio_file = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("dummy audio data"),
      filename: "practice_audio.webm",
      content_type: "audio/webm"
    )

    response = OpenStruct.new(
      body: { text: "こんにちは" }.to_json
    )

    def response.is_a?(klass)
      klass == Net::HTTPSuccess
    end

    http_client = Minitest::Mock.new

    http_client.expect(:start, response) do |host, port, use_ssl:, &block|
      assert_equal "api.groq.com", host
      assert_equal 443, port
      assert_equal true, use_ssl

      http = Minitest::Mock.new

      http.expect(:request, response) do |request|
        assert_equal "Bearer test-api-key", request["Authorization"]
        assert_includes request["Content-Type"], "multipart/form-data"

        body = request.body
        assert_includes body, "name=\"model\""
        assert_includes body, "whisper-large-v3-turbo"
        assert_includes body, "name=\"language\""
        assert_includes body, "ja"
        assert_includes body, "filename=\"practice_audio.webm\""
        assert_includes body, "Content-Type: audio/webm"
      end

      block.call(http)
      http.verify
      true
    end

    original_api_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-api-key"

    begin
      result = GroqTranscriptionService.new(
        audio_file,
        http_client: http_client
      ).call

      assert_equal "こんにちは", result["text"]
      http_client.verify
    ensure
      ENV["GROQ_API_KEY"] = original_api_key
      audio_file.purge
    end
  end
end
