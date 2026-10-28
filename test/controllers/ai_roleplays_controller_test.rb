require "test_helper"
require "open3"

class AiRoleplaysControllerTest < ActionDispatch::IntegrationTest
  # 実際のGroq APIへ通信せず、指定したレスポンスを返すHTTPクライアント
  class FakeGroqHttpClient
    def initialize(response)
      @response = response
      @called = false
    end

    def start(_host, _port, use_ssl:)
      yield self
    end

    def request(_request)
      @called = true
      @response
    end

    def called?
      @called
    end
  end

  VIDEO_FIXTURE = Rails.root.join("test/fixtures/files/test_volume.webm")

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

  test "AI音声の生成時は読み上げ用に変換したテキストを音声合成へ渡す" do
    sign_in @user

    text_to_speech_service = Minitest::Mock.new
    text_to_speech_service.expect(
      :call,
      "fake mp3 data"
    )

    GoogleTextToSpeechService.stub(
      :new,
      ->(text:) {
        assert_equal(
          "毎月ついたちから八千円で、いちにちあたり十ギガバイト使えます。",
          text
        )
        text_to_speech_service
      }
    ) do
      post ai_roleplays_synthesize_path,
           params: {
             text: "毎月1日から8,000円で、1日あたり10GB使えます。"
           }
    end

    assert_response :success
    assert_equal "audio/mpeg", response.media_type

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

    stub_ai_roleplay_evaluation do
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

  test "AIロープレ保存後に保存したセッションの評価を実行する" do
    sign_in @user

    evaluated_sessions = []

    stub_ai_roleplay_evaluation(evaluated_sessions) do
      post ai_roleplays_path,
           params: {
             practice_theme_id: practice_themes(:one).id,
             duration: 120.0,
             end_reason: "user_end",
             conversation_history: roleplay_conversation_history.to_json
           }
    end

    assert_response :created

    session = AiRoleplaySession.order(:created_at).last

    assert_equal({ "id" => session.id }, response.parsed_body)
    assert_equal [ session ], evaluated_sessions
    assert_equal 2, evaluated_sessions.first.ai_roleplay_messages.count
  end

  test "AIロープレの評価に失敗してもセッションと会話履歴は保存され201を返す" do
    sign_in @user

    evaluation_service = Minitest::Mock.new
    evaluation_service.expect(:call, nil) do
      raise "Groq API request failed: 現在インターネットは何をご利用ですか？"
    end

    logged_messages = []

    AiRoleplayEvaluationService.stub(:new, ->(_session) { evaluation_service }) do
      Rails.logger.stub(:error, ->(message = nil) { logged_messages << message }) do
        assert_difference("AiRoleplaySession.count", 1) do
          assert_difference("AiRoleplayMessage.count", 2) do
            assert_no_difference("AiRoleplayEvaluation.count") do
              post ai_roleplays_path,
                   params: {
                     practice_theme_id: practice_themes(:one).id,
                     duration: 120.0,
                     end_reason: "user_end",
                     conversation_history: roleplay_conversation_history.to_json
                   }
            end
          end
        end
      end
    end

    assert_response :created

    session = AiRoleplaySession.order(:created_at).last

    assert_equal({ "id" => session.id }, response.parsed_body)
    assert_equal(
      roleplay_conversation_history.pluck(:content),
      session.ai_roleplay_messages.order(:id).pluck(:content)
    )

    evaluation_service.verify

    assert_equal(
      [ "[AiRoleplaysController#create] AI roleplay evaluation failed: RuntimeError" ],
      logged_messages
    )
  end

  test "AI評価の応答検証に失敗した場合は検証エラーメッセージをログに出力する" do
    sign_in @user

    evaluation_service = Minitest::Mock.new
    evaluation_service.expect(:call, nil) do
      raise AiRoleplayEvaluationService::InvalidResponseError,
            "closing points must be null when score is null"
    end

    logged_messages = []

    AiRoleplayEvaluationService.stub(:new, ->(_session) { evaluation_service }) do
      Rails.logger.stub(:error, ->(message = nil) { logged_messages << message }) do
        post ai_roleplays_path,
             params: {
               practice_theme_id: practice_themes(:one).id,
               duration: 120.0,
               end_reason: "user_end",
               conversation_history: roleplay_conversation_history.to_json
             }
      end
    end

    assert_response :created
    evaluation_service.verify

    assert_equal(
      [
        "[AiRoleplaysController#create] AI roleplay evaluation failed: " \
        "AiRoleplayEvaluationService::InvalidResponseError " \
        "(closing points must be null when score is null)"
      ],
      logged_messages
    )
  end

  test "AI評価の応答検証エラーのログに会話内容・応答本文・APIキーを出力しない" do
    sign_in @user

    original_api_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-api-key"

    # 評価対象外の項目に、会話内容を引用した文章が入った応答を返す
    invalid_evaluation = {
      "hearing" => {
        "score" => 3,
        "good_point" => "現在インターネットは何をご利用ですか？と質問できていました。",
        "improvement_point" => "利用年数も確認しましょう。"
      },
      "listening" => { "score" => nil, "good_point" => nil, "improvement_point" => nil },
      "needs" => { "score" => nil, "good_point" => nil, "improvement_point" => nil },
      "proposal" => { "score" => nil, "good_point" => nil, "improvement_point" => nil },
      "closing" => {
        "score" => nil,
        "good_point" => "今は他社の光回線を使っていますという発言を受けていました。",
        "improvement_point" => nil
      },
      "overall_strength" => "明るく声掛けできていました。",
      "priority_improvement" => "提案につなげる質問を増やしましょう。",
      "next_practice_goal" => "利用状況を3つ以上確認する。"
    }

    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(
      :@body,
      {
        choices: [
          {
            message: { content: invalid_evaluation.to_json },
            finish_reason: "stop"
          }
        ]
      }.to_json
    )
    response.instance_variable_set(:@read, true)

    http_client = FakeGroqHttpClient.new(response)
    original_new = AiRoleplayEvaluationService.method(:new)
    logged_messages = []

    AiRoleplayEvaluationService.stub(
      :new,
      ->(session) { original_new.call(session, http_client: http_client) }
    ) do
      Rails.logger.stub(:error, ->(message = nil) { logged_messages << message }) do
        assert_no_difference("AiRoleplayEvaluation.count") do
          post ai_roleplays_path,
               params: {
                 practice_theme_id: practice_themes(:one).id,
                 duration: 120.0,
                 end_reason: "user_end",
                 conversation_history: roleplay_conversation_history.to_json
               }
        end
      end
    end

    assert_response :created
    assert http_client.called?

    assert_equal(
      [
        "[AiRoleplaysController#create] AI roleplay evaluation failed: " \
        "AiRoleplayEvaluationService::InvalidResponseError " \
        "(closing points must be null when score is null)"
      ],
      logged_messages
    )

    logged_text = logged_messages.join("\n")

    roleplay_conversation_history.each do |message|
      assert_not_includes logged_text, message[:content]
    end
    assert_not_includes logged_text, "光回線"
    assert_not_includes logged_text, "test-api-key"
    assert_not_includes logged_text, "choices"
  ensure
    ENV["GROQ_API_KEY"] = original_api_key
  end

  test "AIロープレのセッション保存に失敗した場合は評価を実行しない" do
    sign_in @user

    conversation_history = [
      {
        role: "system",
        content: "不正なroleです。"
      }
    ]

    AiRoleplayEvaluationService.stub(
      :new,
      ->(_session) { flunk "評価サービスが呼び出されました" }
    ) do
      assert_no_difference("AiRoleplaySession.count") do
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

  test "AIロープレ画面に評価結果画面のURLテンプレートが設定される" do
    sign_in @user

    get ai_roleplay_practice_theme_path(practice_themes(:one))

    assert_response :success
    assert_select(
      '[data-controller="ai-roleplay"][data-ai-roleplay-evaluation-url-value="/ai_roleplays/:id/evaluation"]',
      count: 1
    )
  end

  test "ログインユーザーが自分のAIロープレ評価結果を表示できる" do
    sign_in @user

    evaluation = ai_roleplay_evaluations(:one)
    evaluation.update!(
      hearing_good_point: "家族構成を質問できていました。",
      hearing_improvement_point: "利用年数も確認しましょう。",
      overall_strength: "明るく声掛けできていました。",
      priority_improvement: "提案につなげる質問を増やしましょう。",
      next_practice_goal: "利用状況を3つ以上確認する。"
    )

    get evaluation_ai_roleplay_path(ai_roleplay_sessions(:one))

    assert_response :success
    assert_select "h1", text: "AIロープレ評価結果"
    assert_select "p", text: /#{practice_themes(:one).name}/

    assert_select(
      '[data-ai-roleplay-evaluation-category="hearing"]'
    ) do
      assert_select "h3", text: "ヒアリング"
      assert_select "p", text: "良かった点"
      assert_select "p", text: "家族構成を質問できていました。"
      assert_select "p", text: "改善点"
      assert_select "p", text: "利用年数も確認しましょう。"
    end

    assert_select "h2", text: "総合的な強み"
    assert_select "p", text: "明るく声掛けできていました。"
    assert_select "h2", text: "優先して改善する点"
    assert_select "p", text: "提案につなげる質問を増やしましょう。"
    assert_select "h2", text: "次回の練習目標"
    assert_select "p", text: "利用状況を3つ以上確認する。"
  end

  test "AIロープレ評価結果に5項目の点数・星・顔マークが表示される" do
    sign_in @user

    ai_roleplay_evaluations(:one).update!(
      hearing_score: 1,
      listening_score: 2,
      needs_score: 3,
      proposal_score: 4,
      closing_score: 5
    )

    get evaluation_ai_roleplay_path(ai_roleplay_sessions(:one))

    assert_response :success

    {
      "hearing" => [ "ヒアリング", "20点", "★", "😟" ],
      "listening" => [ "傾聴", "40点", "★★", "😕" ],
      "needs" => [ "ニーズ把握", "60点", "★★★", "😐" ],
      "proposal" => [ "提案", "80点", "★★★★", "🙂" ],
      "closing" => [ "クロージング", "100点", "★★★★★", "😊" ]
    }.each do |category, (label, points, stars, face)|
      assert_select(
        "[data-ai-roleplay-evaluation-category=\"#{category}\"]"
      ) do
        assert_select "h3", text: label
        assert_select "[data-ai-roleplay-evaluation-points]", text: points
        assert_select "[data-ai-roleplay-evaluation-stars]", text: stars
        assert_select "[data-ai-roleplay-evaluation-face]", text: face
        assert_select "[data-ai-roleplay-evaluation-not-applicable]", count: 0
      end
    end
  end

  test "AIロープレ評価結果でスコアがない項目は評価対象外と表示される" do
    sign_in @user

    ai_roleplay_evaluations(:one).update!(
      closing_score: nil,
      closing_good_point: nil,
      closing_improvement_point: nil
    )

    get evaluation_ai_roleplay_path(ai_roleplay_sessions(:one))

    assert_response :success

    assert_select(
      '[data-ai-roleplay-evaluation-category="closing"]'
    ) do
      assert_select "h3", text: "クロージング"
      assert_select "[data-ai-roleplay-evaluation-not-applicable]", text: "評価対象外"
      assert_select "[data-ai-roleplay-evaluation-points]", count: 0
      assert_select "[data-ai-roleplay-evaluation-stars]", count: 0
      assert_select "[data-ai-roleplay-evaluation-face]", count: 0
      assert_select "p", text: "良かった点", count: 0
      assert_select "p", text: "改善点", count: 0
    end

    assert_select(
      '[data-ai-roleplay-evaluation-category="hearing"] [data-ai-roleplay-evaluation-points]',
      text: "20点"
    )
  end

  test "AIロープレ評価結果がない場合は案内と練習テーマへ戻るリンクを表示する" do
    sign_in @user

    session = AiRoleplaySession.create!(
      user: @user,
      practice_theme: practice_themes(:one)
    )

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "p", text: "このロープレの評価結果はありません。"
    assert_select(
      "a[href=?]",
      practice_theme_path(practice_themes(:one)),
      text: "練習テーマへ戻る"
    )
    assert_select "[data-ai-roleplay-evaluation-category]", count: 0
  end

  test "他のユーザーのAIロープレ評価結果は404を返す" do
    sign_in @user

    get evaluation_ai_roleplay_path(ai_roleplay_sessions(:two))

    assert_response :not_found
  end

  test "存在しないAIロープレ評価結果は404を返す" do
    sign_in @user

    get evaluation_ai_roleplay_path(id: 999_999)

    assert_response :not_found
  end

  test "AIロープレ評価結果は未ログインの場合ログイン画面へリダイレクトされる" do
    get evaluation_ai_roleplay_path(ai_roleplay_sessions(:one))

    assert_redirected_to new_user_session_path
  end

  test "発話音声付きでAIロープレを保存すると接客評価と話し方の分析結果を保存する" do
    sign_in @user

    conversation_history = two_turn_conversation_history

    stub_saved_ai_roleplay_evaluation do
      stub_ai_comment do
        assert_difference(
          [ "AiRoleplaySession.count", "AiRoleplayEvaluation.count", "Practice.count", "Analysis.count" ],
          1
        ) do
          assert_difference("AiRoleplayMessage.count", 4) do
            post_ai_roleplay(
              conversation_history: conversation_history,
              clerk_audio_turns: [ clerk_audio, clerk_audio("speech_duration_long_pause.webm") ]
            )
          end
        end
      end
    end

    assert_response :created

    session = AiRoleplaySession.find(response.parsed_body["id"])

    assert_equal({ "id" => session.id }, response.parsed_body)
    assert_not_nil session.ai_roleplay_evaluation

    practice = session.practice

    assert practice.audio.attached?
    assert_equal "ai_roleplay_clerk_audio.webm", practice.audio.filename.to_s
    assert_operator practice.duration, :>, 5.0
    assert_equal(
      conversation_history.select { |message| message[:role] == "user" }.pluck(:content).join("\n"),
      practice.transcription
    )
    assert_not_includes practice.transcription, "今は他社の光回線を使っています。"

    analysis = practice.analysis

    assert_not_nil analysis.speech_speed_score
    assert_not_nil analysis.filler_score
    assert_not_nil analysis.volume_score
    assert_nil analysis.smile_score
  end

  test "話し方の分析結果は今回保存したセッションとログインユーザーに関連付く" do
    sign_in @user

    stub_saved_ai_roleplay_evaluation do
      stub_ai_comment do
        post_ai_roleplay(clerk_audio_turns: [ clerk_audio ])
      end
    end

    assert_response :created

    session = AiRoleplaySession.find(response.parsed_body["id"])
    practice = Practice.find_by!(ai_roleplay_session: session)

    assert_equal session, practice.ai_roleplay_session
    assert_equal practice, session.practice
    assert_equal @user, practice.user
    assert_equal session.practice_theme, practice.practice_theme

    assert_nil ai_roleplay_sessions(:one).practice
    assert_nil ai_roleplay_sessions(:two).practice
  end

  test "発話音声がない場合も接客評価を保存し話し方の分析は行わない" do
    sign_in @user

    stub_saved_ai_roleplay_evaluation do
      assert_difference([ "AiRoleplaySession.count", "AiRoleplayEvaluation.count" ], 1) do
        assert_no_difference([ "Practice.count", "Analysis.count" ]) do
          post_ai_roleplay
        end
      end
    end

    assert_response :created

    session = AiRoleplaySession.find(response.parsed_body["id"])

    assert_equal({ "id" => session.id }, response.parsed_body)
    assert_nil session.practice
  end

  test "発話音声が破損したWebMの場合も接客評価を保存し201を返す" do
    sign_in @user

    logged_messages = []

    stub_saved_ai_roleplay_evaluation do
      Rails.logger.stub(:error, ->(message = nil) { logged_messages << message.to_s }) do
        assert_no_voice_analysis_saved do
          post_ai_roleplay(clerk_audio_turns: [ clerk_audio("test_audio.webm") ])
        end
      end
    end

    assert_response :created
    assert_not_nil AiRoleplaySession.find(response.parsed_body["id"]).ai_roleplay_evaluation

    assert_equal(
      [ "[AiRoleplaysController#create] AI roleplay voice analysis failed: ClerkAudioConcatenator::ConversionError" ],
      logged_messages
    )
  end

  test "発話音声の送信形式が不正な場合も接客評価を保存し201を返す" do
    sign_in @user

    invalid_turns = {
      "配列ではない" => -> { clerk_audio },
      "ファイルではない" => -> { [ "fake audio" ] },
      "音声以外の形式" => -> { [ clerk_audio("test_volume.webm", "text/plain") ] },
      "キー付きのハッシュ" => -> { { "0" => clerk_audio } }
    }

    invalid_turns.each do |label, build_turns|
      logged_messages = []

      stub_saved_ai_roleplay_evaluation do
        Rails.logger.stub(:warn, ->(message = nil) { logged_messages << message.to_s }) do
          assert_no_voice_analysis_saved do
            assert_difference("AiRoleplayEvaluation.count", 1) do
              post_ai_roleplay(clerk_audio_turns: build_turns.call)
            end
          end
        end
      end

      assert_response :created, label
      assert(
        logged_messages.any? do |message|
          message.start_with?(
            "[AiRoleplaysController#create] AI roleplay voice analysis skipped: " \
            "AiRoleplaysController::InvalidClerkAudioError"
          )
        end,
        "#{label}の場合に入力検証のログが出力されていません"
      )
    end
  end

  test "発話音声の件数・1件あたりのサイズ・合計サイズが上限を超える場合は分析せず201を返す" do
    sign_in @user

    conversation_history = two_turn_conversation_history

    limits = {
      "件数" => [ :MAX_FILES, 1, "AiRoleplaysController::InvalidClerkAudioError" ],
      "1件あたりのサイズ" => [ :MAX_FILE_SIZE, 1, "ClerkAudioConcatenator::InvalidInputError" ],
      "合計サイズ" => [ :MAX_TOTAL_SIZE, File.size(file_fixture("test_volume.webm")) + 1, "ClerkAudioConcatenator::InvalidInputError" ]
    }

    limits.each do |label, (const_name, value, error_class)|
      logged_messages = []

      with_stubbed_concatenator_const(const_name, value) do
        stub_saved_ai_roleplay_evaluation do
          Open3.stub(:capture3, ->(*_args) { flunk "#{label}の上限超過時にffmpegを実行しないこと" }) do
            Rails.logger.stub(:warn, ->(message = nil) { logged_messages << message.to_s }) do
              assert_no_voice_analysis_saved do
                assert_difference("AiRoleplayEvaluation.count", 1) do
                  post_ai_roleplay(
                    conversation_history: conversation_history,
                    clerk_audio_turns: [ clerk_audio, clerk_audio ]
                  )
                end
              end
            end
          end
        end
      end

      assert_response :created, label
      assert(
        logged_messages.any? { |message| message.include?("voice analysis skipped: #{error_class}") },
        "#{label}の上限超過のログが出力されていません"
      )
    end
  end

  test "話し方の分析サービスが例外を出しても接客評価を保存しログには例外クラスだけを出す" do
    sign_in @user

    original_api_key = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-api-key"

    voice_analysis_service = Object.new

    def voice_analysis_service.call
      raise "分析に失敗: 現在インターネットは何をご利用ですか？ test-api-key"
    end

    logged_messages = []

    stub_saved_ai_roleplay_evaluation do
      AiRoleplayVoiceAnalysisService.stub(:new, ->(**_args) { voice_analysis_service }) do
        Rails.logger.stub(:error, ->(message = nil) { logged_messages << message.to_s }) do
          assert_difference([ "AiRoleplaySession.count", "AiRoleplayEvaluation.count" ], 1) do
            assert_no_difference([ "Practice.count", "Analysis.count" ]) do
              post_ai_roleplay(clerk_audio_turns: [ clerk_audio ])
            end
          end
        end
      end
    end

    assert_response :created

    session = AiRoleplaySession.find(response.parsed_body["id"])

    assert_equal({ "id" => session.id }, response.parsed_body)
    assert_equal(
      roleplay_conversation_history.pluck(:content),
      session.ai_roleplay_messages.order(:id).pluck(:content)
    )

    assert_equal(
      [ "[AiRoleplaysController#create] AI roleplay voice analysis failed: RuntimeError" ],
      logged_messages
    )
    assert_not_includes logged_messages.join("\n"), "インターネット"
    assert_not_includes logged_messages.join("\n"), "test-api-key"
  ensure
    ENV["GROQ_API_KEY"] = original_api_key
  end

  test "接客内容の評価に失敗しても話し方の分析は実行する" do
    sign_in @user

    evaluation_service = Object.new

    def evaluation_service.call
      raise "Groq API request failed"
    end

    AiRoleplayEvaluationService.stub(:new, ->(_session) { evaluation_service }) do
      stub_ai_comment do
        assert_no_difference("AiRoleplayEvaluation.count") do
          assert_difference([ "Practice.count", "Analysis.count" ], 1) do
            post_ai_roleplay(clerk_audio_turns: [ clerk_audio ])
          end
        end
      end
    end

    assert_response :created
  end

  test "発言数と発話音声数が一致せず話し方の分析をスキップした場合も正常に応答する" do
    sign_in @user

    logged_messages = []

    stub_saved_ai_roleplay_evaluation do
      Open3.stub(:capture3, ->(*_args) { flunk "ffmpegを実行しないこと" }) do
        Rails.logger.stub(:info, ->(message = nil) { logged_messages << message.to_s }) do
          assert_no_voice_analysis_saved do
            post_ai_roleplay(clerk_audio_turns: [ clerk_audio, clerk_audio ])
          end
        end
      end
    end

    assert_response :created

    session = AiRoleplaySession.find(response.parsed_body["id"])

    assert_equal({ "id" => session.id }, response.parsed_body)
    assert_not_nil session.ai_roleplay_evaluation
    assert(
      logged_messages.any? { |message| message.include?("発言数（1件）と発話音声数（2件）が一致しません") }
    )
  end

  test "話し方の分析結果はセッションごとに1件だけ作成され重複しない" do
    sign_in @user

    session_ids = []

    stub_saved_ai_roleplay_evaluation do
      stub_ai_comment do
        assert_difference([ "Practice.count", "Analysis.count" ], 2) do
          2.times do
            post_ai_roleplay(clerk_audio_turns: [ clerk_audio ])
            assert_response :created
            session_ids << response.parsed_body["id"]
          end
        end
      end
    end

    assert_equal 2, session_ids.uniq.size
    session_ids.each do |session_id|
      assert_equal 1, Practice.where(ai_roleplay_session_id: session_id).count
    end

    session = AiRoleplaySession.find(session_ids.first)

    File.open(file_fixture("test_volume.webm"), "rb") do |file|
      assert_no_difference([ "Practice.count", "Analysis.count" ]) do
        assert_nil AiRoleplayVoiceAnalysisService.new(ai_roleplay_session: session, audio_files: [ file ]).call
      end
    end
  end

  test "未ログインの場合は発話音声付きでも保存も分析も行わない" do
    assert_no_difference([ "AiRoleplaySession.count", "AiRoleplayEvaluation.count" ]) do
      assert_no_voice_analysis_saved do
        post_ai_roleplay(clerk_audio_turns: [ clerk_audio ])
      end
    end

    assert_redirected_to new_user_session_path
  end

  test "話し方の分析を行ったAIロープレの評価結果は他のユーザーから参照できない" do
    sign_in @user

    stub_saved_ai_roleplay_evaluation do
      stub_ai_comment do
        post_ai_roleplay(clerk_audio_turns: [ clerk_audio ])
      end
    end

    session = AiRoleplaySession.find(response.parsed_body["id"])

    assert_not_nil session.practice

    sign_out @user
    sign_in users(:two)

    get evaluation_ai_roleplay_path(session)

    assert_response :not_found
  end

  test "AIロープレ評価結果に接客内容の評価5項目と話し方の分析3項目を分けて表示する" do
    sign_in @user

    session = ai_roleplay_sessions(:one)

    ai_roleplay_evaluations(:one).update!(
      hearing_score: 1,
      listening_score: 2,
      needs_score: 3,
      proposal_score: 4,
      closing_score: 5
    )

    create_voice_analysis(session)

    get evaluation_ai_roleplay_path(session)

    assert_response :success

    {
      "hearing" => "20点",
      "listening" => "40点",
      "needs" => "60点",
      "proposal" => "80点",
      "closing" => "100点"
    }.each do |category, points|
      assert_select(
        "[data-ai-roleplay-evaluation-category=\"#{category}\"] [data-ai-roleplay-evaluation-points]",
        text: points
      )
    end

    assert_select "[data-ai-roleplay-voice-analysis]" do
      assert_select "h2", text: "話し方の分析（参考）"
      assert_select "[data-ai-roleplay-voice-analysis-item]", count: 3
      assert_select "[data-ai-roleplay-evaluation-category]", count: 0
      assert_select "[data-ai-roleplay-voice-analysis-empty]", count: 0
    end

    {
      "speech_speed" => [ "話速", "83点", "7.25 文字/秒" ],
      "filler" => [ "フィラー", "64点", "フィラー回数：3回" ],
      "volume" => [ "声量", "91点", "声量：-21.3 dB" ]
    }.each do |item, (label, score, value)|
      assert_select "[data-ai-roleplay-voice-analysis-item=\"#{item}\"]" do
        assert_select "h3", text: label
        assert_select "[data-ai-roleplay-voice-analysis-score]", text: score
        assert_select "[data-ai-roleplay-voice-analysis-value]", text: value
      end
    end

    # 接客内容の評価の後に話し方の分析を表示する
    body = response.body
    assert_operator(
      body.index("data-ai-roleplay-evaluation-category=\"closing\""),
      :<,
      body.index("data-ai-roleplay-voice-analysis-item=\"speech_speed\"")
    )
  end

  test "話し方の分析は総合スコアを表示せず接客内容の評価点と合算しない" do
    sign_in @user

    session = ai_roleplay_sessions(:one)

    ai_roleplay_evaluations(:one).update!(
      hearing_score: 1,
      listening_score: 2,
      needs_score: 3,
      proposal_score: 4,
      closing_score: 5
    )

    create_voice_analysis(session, total_score: 987)

    get evaluation_ai_roleplay_path(session)

    assert_response :success

    page_text = css_select("body").text
    voice_text = css_select("[data-ai-roleplay-voice-analysis]").text

    assert_not_includes page_text, "987"
    assert_not_includes page_text, "総合スコア"
    assert_not_includes voice_text, "総合"
    assert_not_includes voice_text, "合計"

    # 接客内容の5項目（300点）と話し方の3項目（238点）を合算・平均した値を表示しない
    [ "538", "67", "238" ].each do |combined|
      assert_not_includes page_text, "#{combined}点"
    end

    assert_select(
      '[data-ai-roleplay-evaluation-category="hearing"] [data-ai-roleplay-evaluation-points]',
      text: "20点"
    )
    assert_select "[data-ai-roleplay-voice-analysis-score]", count: 3
  end

  test "話し方の分析のAIコメントを改善アドバイスとして表示する" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    create_voice_analysis(session, ai_comment: "語尾まではっきり話すと、より伝わりやすくなります。")

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "[data-ai-roleplay-voice-analysis-advice]" do
      assert_select "p", text: "改善アドバイス"
      assert_select "p", text: "語尾まではっきり話すと、より伝わりやすくなります。"
    end
  end

  test "話し方の分析のAIコメントがない場合は改善アドバイスを表示しない" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    create_voice_analysis(session, ai_comment: nil)

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "[data-ai-roleplay-voice-analysis-item]", count: 3
    assert_select "[data-ai-roleplay-voice-analysis-advice]", count: 0
  end

  test "音声分析のない過去のAIロープレは接客内容の評価と分析結果がない旨を表示する" do
    sign_in @user

    session = ai_roleplay_sessions(:one)

    assert_nil session.practice

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "[data-ai-roleplay-evaluation-category]", count: 5
    assert_select "h2", text: "総合的な強み"
    assert_select "[data-ai-roleplay-voice-analysis]" do
      assert_select "h2", text: "話し方の分析（参考）"
      assert_select "[data-ai-roleplay-voice-analysis-empty]", text: "話し方の分析結果はありません"
      assert_select "[data-ai-roleplay-voice-analysis-item]", count: 0
    end
  end

  test "音声分析用のPracticeにAnalysisがない場合も分析結果がない旨を表示する" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    Practice.create!(user: @user, practice_theme: session.practice_theme, ai_roleplay_session: session)

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "[data-ai-roleplay-voice-analysis-empty]", text: "話し方の分析結果はありません"
    assert_select "[data-ai-roleplay-voice-analysis-item]", count: 0
  end

  test "接客内容の評価がなく話し方の分析だけがある場合は両方の状態を表示する" do
    sign_in @user

    session = AiRoleplaySession.create!(user: @user, practice_theme: practice_themes(:one))
    create_voice_analysis(session)

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "p", text: "このロープレの評価結果はありません。"
    assert_select "[data-ai-roleplay-evaluation-category]", count: 0
    assert_select "[data-ai-roleplay-voice-analysis-item]", count: 3
  end

  test "話し方の分析結果は関連データを一括で読み込みN+1クエリを発生させない" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    create_voice_analysis(session)

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    begin
      get evaluation_ai_roleplay_path(session)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_response :success
    assert_select "[data-ai-roleplay-voice-analysis-item]", count: 3

    assert_equal 1, queries.count { |sql| sql.match?(/FROM "practices"/) }
    assert_equal 1, queries.count { |sql| sql.match?(/FROM "analyses"/) }

    # 1件の表示ではクエリ数が遅延読み込みと変わらないため、
    # has_oneの遅延読み込みで付くLIMITがなく、includesで一括読み込みしていることを確認する
    queries.select { |sql| sql.match?(/FROM "(practices|analyses)"/) }.each do |sql|
      assert_no_match(/LIMIT/, sql)
    end
  end

  test "他のユーザーの話し方の分析結果を含む評価結果は表示できない" do
    other_session = ai_roleplay_sessions(:two)
    create_voice_analysis(other_session, ai_comment: "他のユーザーへのアドバイスです。")

    sign_in @user

    get evaluation_ai_roleplay_path(other_session)

    assert_response :not_found
    # テスト環境の404画面にはテストコードの抜粋が表示されるため、本文ではなく表示要素の有無で確認する
    assert_select "[data-ai-roleplay-voice-analysis]", count: 0
  end

  test "話し方の分析結果を含む評価結果は未ログインの場合ログイン画面へリダイレクトされる" do
    session = ai_roleplay_sessions(:one)
    create_voice_analysis(session, ai_comment: "ログインユーザー向けのアドバイスです。")

    get evaluation_ai_roleplay_path(session)

    assert_redirected_to new_user_session_path
    assert_not_includes response.body, "ログインユーザー向けのアドバイスです。"
  end

  test "本人の録画URLはストレージの期限付きURLへ302で転送する" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)

    get video_ai_roleplay_path(session)

    assert_response :found
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/disk/}, response.location
    assert_includes response.location, "ai_roleplay.webm"
  end

  test "録画の転送レスポンスはブラウザに保存させずリファラーも送らない" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)

    get video_ai_roleplay_path(session)

    assert_response :found
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "転送先の期限付きURLから録画を取得でき30分を過ぎると取得できない" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)

    get video_ai_roleplay_path(session)
    video_url = response.location

    get video_url

    assert_response :success
    assert_equal File.binread(VIDEO_FIXTURE), response.body

    travel 29.minutes do
      get video_url

      assert_response :success
    end

    travel 31.minutes do
      get video_url

      assert_response :not_found
    end
  end

  test "他のユーザーの録画URLは404を返し転送しない" do
    sign_in @user

    other_session = ai_roleplay_sessions(:two)
    attach_video(other_session)

    get video_ai_roleplay_path(other_session)

    assert_response :not_found
    assert_nil response.headers["Location"]
  end

  test "録画URLは未ログインの場合ログイン画面へリダイレクトされ動画へ転送しない" do
    session = ai_roleplay_sessions(:one)
    attach_video(session)

    get video_ai_roleplay_path(session)

    assert_redirected_to new_user_session_path
    assert_not_includes response.location, "active_storage"
  end

  test "存在しないAIロープレの録画URLは404を返す" do
    sign_in @user

    get video_ai_roleplay_path(id: 999_999)

    assert_response :not_found
  end

  test "録画がないAIロープレの録画URLは404を返す" do
    sign_in @user

    session = ai_roleplay_sessions(:one)

    assert_not session.video.attached?

    get video_ai_roleplay_path(session)

    assert_response :not_found
    assert_nil response.headers["Location"]
  end

  test "録画の転送先URLをログに出力しない" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)

    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    original_rails_logger = Rails.logger
    original_controller_logger = ActionController::Base.logger

    begin
      Rails.logger = logger
      ActionController::Base.logger = logger

      get video_ai_roleplay_path(session)
    ensure
      Rails.logger = original_rails_logger
      ActionController::Base.logger = original_controller_logger
    end

    assert_response :found
    assert_includes log.string, "AiRoleplaysController#video"
    assert_not_includes log.string, response.location
    assert_not_includes log.string, "/rails/active_storage/disk/"
  end

  test "録画があるAIロープレの評価結果に録画データの動画を表示する" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "[data-ai-roleplay-video]" do
      assert_select "h2", text: "録画データ"
      assert_select(
        "video[src=?][controls][preload=metadata].w-100.rounded",
        video_ai_roleplay_path(session)
      )
      assert_select "[data-ai-roleplay-video-empty]", count: 0
    end
  end

  test "録画データのカードは話し方の分析の後に表示する" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_operator(
      response.body.index("data-ai-roleplay-voice-analysis"),
      :<,
      response.body.index("data-ai-roleplay-video")
    )
  end

  test "録画がないAIロープレの評価結果は録画データがない旨を表示する" do
    sign_in @user

    get evaluation_ai_roleplay_path(ai_roleplay_sessions(:one))

    assert_response :success
    assert_select "[data-ai-roleplay-video]" do
      assert_select "h2", text: "録画データ"
      assert_select "[data-ai-roleplay-video-empty]", text: "録画データはありません"
      assert_select "video", count: 0
    end
  end

  test "評価結果にActive Storageの期限のない公開URLを出力しない" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)
    create_voice_analysis(session)

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "video", count: 1
    assert_not_includes response.body, "/rails/active_storage/"
    assert_not_includes response.body, session.video.blob.signed_id
  end

  test "接客内容の評価も話し方の分析もない過去のAIロープレでも録画データを表示する" do
    sign_in @user

    session = AiRoleplaySession.create!(
      user: @user,
      practice_theme: practice_themes(:one),
      created_at: 30.days.ago
    )
    attach_video(session)

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "p", text: "このロープレの評価結果はありません。"
    assert_select "[data-ai-roleplay-voice-analysis-empty]", text: "話し方の分析結果はありません"
    assert_select "[data-ai-roleplay-video] video[src=?]", video_ai_roleplay_path(session)
  end

  test "評価結果の録画は添付情報を一括で読み込む" do
    sign_in @user

    session = ai_roleplay_sessions(:one)
    attach_video(session)

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    begin
      get evaluation_ai_roleplay_path(session)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_response :success
    assert_select "[data-ai-roleplay-video] video", count: 1

    attachment_queries = queries.select { |sql| sql.match?(/FROM "active_storage_(attachments|blobs)"/) }

    assert_not_empty attachment_queries
    # 遅延読み込みで付くLIMITがなく、with_attached_videoで一括読み込みしていることを確認する
    attachment_queries.each { |sql| assert_no_match(/LIMIT/, sql) }
  end

  private

  def attach_video(session)
    session.video.attach(
      io: StringIO.new(File.binread(VIDEO_FIXTURE)),
      filename: "ai_roleplay.webm",
      content_type: "video/webm"
    )
  end

  def create_voice_analysis(session, **attributes)
    practice = Practice.create!(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session,
      duration: 30.0,
      transcription: "いらっしゃいませ"
    )

    practice.create_analysis!(
      {
        total_score: 79,
        speech_speed: 7.25,
        speech_speed_score: 83,
        filler_count: 3,
        filler_score: 64,
        volume: -21.3,
        volume_score: 91,
        ai_comment: "テスト用のAIコメントです。"
      }.merge(attributes)
    )
  end

  # 接客内容の評価結果を保存する評価サービスに差し替える
  def stub_saved_ai_roleplay_evaluation(&block)
    AiRoleplayEvaluationService.stub(
      :new,
      lambda { |session|
        Struct.new(:session) do
          def call
            AiRoleplayEvaluation.create!(ai_roleplay_session: session, hearing_score: 4)
          end
        end.new(session)
      },
      &block
    )
  end

  # テスト中に実際のGroq APIへ通信しないよう、話し方の分析のAIコメント生成を差し替える
  def stub_ai_comment(&block)
    AiCommentService.stub(
      :new,
      ->(_analysis) { Struct.new(:call).new("テスト用のAIコメントです。") },
      &block
    )
  end

  def post_ai_roleplay(conversation_history: roleplay_conversation_history, clerk_audio_turns: nil)
    params = {
      practice_theme_id: practice_themes(:one).id,
      duration: 120.0,
      end_reason: "user_end",
      conversation_history: conversation_history.to_json
    }
    params[:clerk_audio_turns] = clerk_audio_turns unless clerk_audio_turns.nil?

    post ai_roleplays_path, params: params
  end

  def clerk_audio(filename = "test_volume.webm", content_type = "audio/webm;codecs=opus")
    fixture_file_upload(filename, content_type)
  end

  def assert_no_voice_analysis_saved(&block)
    assert_no_difference(
      [
        "Practice.count",
        "Analysis.count",
        "ActiveStorage::Blob.where(filename: AiRoleplayVoiceAnalysisService::AUDIO_FILENAME).count"
      ],
      &block
    )
  end

  def with_stubbed_concatenator_const(name, value)
    original = ClerkAudioConcatenator.const_get(name)

    ClerkAudioConcatenator.send(:remove_const, name)
    ClerkAudioConcatenator.const_set(name, value)

    yield
  ensure
    ClerkAudioConcatenator.send(:remove_const, name)
    ClerkAudioConcatenator.const_set(name, original)
  end

  def two_turn_conversation_history
    [
      { role: "user", content: "現在インターネットは何をご利用ですか？" },
      { role: "assistant", content: "今は他社の光回線を使っています。" },
      { role: "user", content: "えーと、ご利用年数はどのくらいですか。" },
      { role: "assistant", content: "5年くらいです。" }
    ]
  end

  # テスト中に実際のGroq APIへ通信しないよう、評価サービスを差し替える
  def stub_ai_roleplay_evaluation(evaluated_sessions = [], &block)
    evaluation_services = []

    AiRoleplayEvaluationService.stub(
      :new,
      lambda { |session|
        evaluated_sessions << session

        evaluation_service = Minitest::Mock.new
        evaluation_service.expect(:call, nil)
        evaluation_services << evaluation_service
        evaluation_service
      },
      &block
    )

    evaluation_services.each(&:verify)
  end

  def roleplay_conversation_history
    [
      {
        role: "user",
        content: "現在インターネットは何をご利用ですか？"
      },
      {
        role: "assistant",
        content: "今は他社の光回線を使っています。"
      }
    ]
  end
end
