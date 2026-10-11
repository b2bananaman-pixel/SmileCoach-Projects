require "test_helper"

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

  private

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
