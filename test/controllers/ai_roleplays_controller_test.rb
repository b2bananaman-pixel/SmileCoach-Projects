require "test_helper"

class AiRoleplaysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "ログインユーザーがAIロープレ画面を表示できる" do
    sign_in @user

    practice_theme = practice_themes(:one)

    get ai_roleplay_practice_theme_path(practice_theme)

    assert_response :success
    assert_select "h1", text: "AIロープレ"
    assert_includes response.body, practice_theme.name
  end

  test "AIロープレ画面に指定した練習テーマが表示される" do
    sign_in @user

    practice_theme = practice_themes(:one)

    get ai_roleplay_practice_theme_path(practice_theme)

    assert_response :success
    assert_select(
      "p",
      text: /#{Regexp.escape(practice_theme.name)}/
    )
  end

  test "AIロープレ画面にロープレ開始用UIが表示される" do
    sign_in @user

    practice_theme = practice_themes(:one)

    get ai_roleplay_practice_theme_path(practice_theme)

    assert_response :success

    assert_select(
      '[data-controller="ai-roleplay"]',
      count: 1
    )

    assert_select(
      '[data-ai-roleplay-target="timer"]',
      text: "10:00",
      count: 1
    )

    assert_select(
      'video[data-ai-roleplay-target="preview"]',
      count: 1
    )

    assert_select(
      '[data-ai-roleplay-target="recordingIndicator"]',
      text: /録画準備中/,
      count: 1
    )

    assert_select "h2", text: "AI顧客"

    assert_select(
      'button[data-ai-roleplay-target="stopTurnButton"]',
      text: "話し終わる",
      count: 1
    )

    assert_select(
      'button[data-ai-roleplay-target="endRoleplayButton"]',
      text: "ロープレを終了する",
      count: 1
    )
  end

  test "AIロープレ画面は未ログインの場合ログイン画面へリダイレクトされる" do
    practice_theme = practice_themes(:one)

    get ai_roleplay_practice_theme_path(practice_theme)

    assert_redirected_to new_user_session_path
  end

  test "存在しない練習テーマのAIロープレ画面は404を返す" do
    sign_in @user

    get ai_roleplay_practice_theme_path(id: 999_999)

    assert_response :not_found
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
      ->(clerk_message:, conversation_history:) {
        assert_equal(
          "今日はスマートフォンのお乗り換えをご検討ですか？",
          clerk_message
        )
        assert_equal [], conversation_history

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

  test "会話履歴をAI顧客返答サービスへ渡せる" do
    sign_in @user

    conversation_history = [
      {
        role: "user",
        content: "現在の料金は高いと感じていますか？"
      },
      {
        role: "assistant",
        content: "はい、最近少し高いと感じています。"
      }
    ]

    ai_response = {
      "reply" => "4人で使っています。",
      "customer_state" => "neutral",
      "contract_intent" => "considering",
      "reason" => "家族構成について回答した",
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
      ->(clerk_message:, conversation_history:) {
        assert_equal(
          "ご家族は何人で利用されていますか？",
          clerk_message
        )

        assert_equal(
          [
            {
              "role" => "user",
              "content" => "現在の料金は高いと感じていますか？"
            },
            {
              "role" => "assistant",
              "content" => "はい、最近少し高いと感じています。"
            }
          ],
          conversation_history
        )

        roleplay_service
      }
    ) do
      post ai_roleplays_respond_path,
           params: {
             clerk_message: "ご家族は何人で利用されていますか？",
             conversation_history: conversation_history.to_json
           }
    end

    assert_response :success
    assert_equal(
      "4人で使っています。",
      response.parsed_body["reply"]
    )

    roleplay_service.verify
  end

  test "会話履歴が不正なJSONの場合は422を返す" do
    sign_in @user

    post ai_roleplays_respond_path,
         params: {
           clerk_message: "こんにちは。",
           conversation_history: "{invalid-json"
         }

    assert_response :unprocessable_entity
    assert_equal(
      { "error" => "会話履歴の形式が不正です" },
      response.parsed_body
    )
  end

  test "会話履歴が配列ではない場合は422を返す" do
    sign_in @user

    post ai_roleplays_respond_path,
         params: {
           clerk_message: "こんにちは。",
           conversation_history: {
             role: "user",
             content: "こんにちは。"
           }.to_json
         }

    assert_response :unprocessable_entity
    assert_equal(
      {
        "error" =>
          "conversation_history must be an array"
      },
      response.parsed_body
    )
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
      ->(clerk_message:, conversation_history:) {
        assert_equal "こんにちは。", clerk_message
        assert_equal [], conversation_history

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
  test "ログインユーザーがAIロープレ記録を保存できる" do
    sign_in @user

    video = fixture_file_upload(
      "test_audio.webm",
      "video/webm"
    )

    conversation_history = [
      {
        role: "user",
        content: "現在インターネットは何をご利用ですか？"
      },
      {
        role: "assistant",
        content: "今は他社の光回線を使っています。"
      }
    ]

    assert_difference("AiRoleplaySession.count", 1) do
      assert_difference("AiRoleplayMessage.count", 2) do
        post ai_roleplays_path,
             params: {
               practice_theme_id: practice_themes(:one).id,
               video: video,
               duration: 120.5,
               end_reason: "user_end",
               started_at: "2026-10-04T10:00:00+09:00",
               ended_at: "2026-10-04T10:02:00+09:00",
               conversation_history: conversation_history.to_json
             }
      end
    end

    assert_response :created

    session = AiRoleplaySession.order(:created_at).last

    assert_equal @user, session.user
    assert_equal practice_themes(:one), session.practice_theme
    assert_equal 120.5, session.duration
    assert_equal "user_end", session.end_reason
    assert session.video.attached?

    assert_equal(
      %w[user assistant],
      session.ai_roleplay_messages.order(:id).pluck(:role)
    )

    assert_equal(
      [
        "現在インターネットは何をご利用ですか？",
        "今は他社の光回線を使っています。"
      ],
      session.ai_roleplay_messages.order(:id).pluck(:content)
    )
  end

  test "AIロープレ記録は未ログインの場合保存できない" do
    assert_no_difference("AiRoleplaySession.count") do
      post ai_roleplays_path,
           params: {
             practice_theme_id: practice_themes(:one).id,
             duration: 120.0,
             end_reason: "user_end",
             conversation_history: [].to_json
           }
    end

    assert_redirected_to new_user_session_path
  end

  test "AIロープレ保存時の会話履歴が不正なJSONの場合は422を返す" do
    sign_in @user

    assert_no_difference("AiRoleplaySession.count") do
      post ai_roleplays_path,
           params: {
             practice_theme_id: practice_themes(:one).id,
             duration: 120.0,
             end_reason: "user_end",
             conversation_history: "{invalid-json"
           }
    end

    assert_response :unprocessable_entity
    assert_equal(
      { "error" => "会話履歴の形式が不正です" },
      response.parsed_body
    )
  end

  test "AIロープレ保存時の会話履歴が配列ではない場合は422を返す" do
    sign_in @user

    assert_no_difference("AiRoleplaySession.count") do
      post ai_roleplays_path,
           params: {
             practice_theme_id: practice_themes(:one).id,
             duration: 120.0,
             end_reason: "user_end",
             conversation_history: {
               role: "user",
               content: "こんにちは。"
             }.to_json
           }
    end

    assert_response :unprocessable_entity
  end
    test "会話履歴に不正なroleがある場合はセッションごと保存されない" do
    sign_in @user

    conversation_history = [
      {
        role: "user",
        content: "こんにちは。"
      },
      {
        role: "system",
        content: "不正なroleです。"
      }
    ]

    assert_no_difference("AiRoleplaySession.count") do
      assert_no_difference("AiRoleplayMessage.count") do
        post ai_roleplays_path,
             params: {
               practice_theme_id: practice_themes(:one).id,
               duration: 120.0,
               end_reason: "user_end",
               conversation_history: conversation_history.to_json
             }
      end
    end

    assert_response :unprocessable_entity
  end
end
