require "test_helper"

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
end
