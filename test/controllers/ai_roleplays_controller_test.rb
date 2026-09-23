require "test_helper"

class AiRoleplaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "ログインユーザーがAI音声を生成できる" do
    sign_in @user

    fake_audio = "fake mp3 data"

    text_to_speech_service = Minitest::Mock.new
    text_to_speech_service.expect(
      :call,
      fake_audio
    )

    GoogleTextToSpeechService.stub(
      :new,
      ->(text:) {
        assert_equal "こんにちは。いらっしゃいませ。", text
        text_to_speech_service
      }
    ) do
      post ai_roleplays_synthesize_path,
           params: {
             text: "こんにちは。いらっしゃいませ。"
           }
    end

    assert_response :success
    assert_equal "audio/mpeg", response.media_type
    assert_equal fake_audio, response.body

    text_to_speech_service.verify
  end

  test "textがない場合は422を返す" do
    sign_in @user

    post ai_roleplays_synthesize_path,
         params: {}

    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "text"
  end

  test "未ログインの場合はログイン画面へリダイレクトされる" do
    post ai_roleplays_synthesize_path,
         params: {
           text: "こんにちは。"
         }

    assert_redirected_to new_user_session_path
  end

  test "音声生成に失敗した場合は502を返す" do
    sign_in @user

    text_to_speech_service = Object.new

    def text_to_speech_service.call
      raise "Google TTS test error"
    end

    GoogleTextToSpeechService.stub(
      :new,
      ->(text:) {
        assert_equal "こんにちは。", text
        text_to_speech_service
      }
    ) do
      post ai_roleplays_synthesize_path,
           params: {
             text: "こんにちは。"
           }
    end

    assert_response :bad_gateway
    assert_equal(
      { "error" => "音声の生成に失敗しました" },
      response.parsed_body
    )
  end

  test "ログインユーザーがAI顧客の1ターン返答を取得できる" do
    sign_in @user

    ai_response = {
      "reply" => "はい、乗り換えを検討しています。",
      "customer_state" => "interested",
      "contract_intent" => "considering",
      "reason" => "料金を見直したい",
      "conversation_end" => false,
      "end_reason" => nil
    }

    roleplay_service = Minitest::Mock.new
    roleplay_service.expect(
      :call,
      ai_response
    )

    AiRoleplayResponseService.stub(
      :new,
      ->(clerk_message:) {
        assert_equal(
          "今日はスマートフォンのお乗り換えをご検討ですか？",
          clerk_message
        )

        roleplay_service
      }
    ) do
      post ai_roleplays_respond_path,
           params: {
             clerk_message: "今日はスマートフォンのお乗り換えをご検討ですか？"
           }
    end

    assert_response :success

    body = response.parsed_body

    assert_equal(
      "はい、乗り換えを検討しています。",
      body["reply"]
    )
    assert_equal "interested", body["customer_state"]
    assert_equal "considering", body["contract_intent"]
    assert_equal "料金を見直したい", body["reason"]
    assert_equal false, body["conversation_end"]
    assert_nil body["end_reason"]

    roleplay_service.verify
  end

  test "1ターン返答でclerk_messageがない場合は422を返す" do
    sign_in @user

    post ai_roleplays_respond_path,
         params: {}

    assert_response :unprocessable_entity
    assert_includes(
      response.parsed_body["error"],
      "clerk_message"
    )
  end

  test "1ターン返答は未ログインの場合ログイン画面へリダイレクトされる" do
    post ai_roleplays_respond_path,
         params: {
           clerk_message: "こんにちは。"
         }

    assert_redirected_to new_user_session_path
  end

  test "AI顧客の返答生成に失敗した場合は502を返す" do
    sign_in @user

    roleplay_service = Object.new

    def roleplay_service.call
      raise "Groq test error"
    end

    AiRoleplayResponseService.stub(
      :new,
      ->(clerk_message:) {
        assert_equal "こんにちは。", clerk_message
        roleplay_service
      }
    ) do
      post ai_roleplays_respond_path,
           params: {
             clerk_message: "こんにちは。"
           }
    end

    assert_response :bad_gateway
    assert_equal(
      { "error" => "AI顧客の返答生成に失敗しました" },
      response.parsed_body
    )
  end

  test "ログインユーザーが店員音声を文字起こしできる" do
    sign_in @user

    audio = fixture_file_upload(
      "test_audio.webm",
      "audio/webm"
    )

    transcription_service = Minitest::Mock.new
    transcription_service.expect(
      :call,
      "いらっしゃいませ。今日はお乗り換えをご検討ですか？"
    )

    GuestTranscriptionService.stub(
      :new,
      ->(audio_file) {
        assert_respond_to audio_file, :path
        assert File.exist?(audio_file.path)

        transcription_service
      }
    ) do
      post ai_roleplays_transcribe_path,
           params: {
             audio: audio
           }
    end

    assert_response :success
    assert_equal(
      {
        "transcription" =>
          "いらっしゃいませ。今日はお乗り換えをご検討ですか？"
      },
      response.parsed_body
    )

    transcription_service.verify
  end

  test "文字起こしでaudioがない場合は422を返す" do
    sign_in @user

    post ai_roleplays_transcribe_path,
         params: {}

    assert_response :unprocessable_entity
    assert_includes(
      response.parsed_body["error"],
      "audio"
    )
  end

  test "文字起こしは未ログインの場合ログイン画面へリダイレクトされる" do
    audio = fixture_file_upload(
      "test_audio.webm",
      "audio/webm"
    )

    post ai_roleplays_transcribe_path,
         params: {
           audio: audio
         }

    assert_redirected_to new_user_session_path
  end

  test "文字起こしに失敗した場合は502を返す" do
    sign_in @user

    audio = fixture_file_upload(
      "test_audio.webm",
      "audio/webm"
    )

    transcription_service = Object.new

    def transcription_service.call
      raise "Groq transcription test error"
    end

    GuestTranscriptionService.stub(
      :new,
      ->(_audio_file) {
        transcription_service
      }
    ) do
      post ai_roleplays_transcribe_path,
           params: {
             audio: audio
           }
    end

    assert_response :bad_gateway
    assert_equal(
      { "error" => "音声の文字起こしに失敗しました" },
      response.parsed_body
    )
  end
end
