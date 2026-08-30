
require "test_helper"

class PracticeThemesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)

    sign_in @user

    @practice_theme = PracticeTheme.create!(
      name: "家電の提案販売",
      description: "お客様像：冷蔵庫売り場に来店している30代くらいの男女。現在使用している冷蔵庫が古くなり、買い替えを検討している。\n\n接客条件：\n① お客様へ明るく声掛けをする\n② 現在の利用状況を確認する\n③ お客様に合ったサービスを提案する"
    )
  end

  test "should get index" do
    get practice_themes_url

    assert_response :success
    assert_select "h1", "練習テーマを選択"
    assert_select "h2", "家電の提案販売"
  end

  test "should get selected practice theme" do
    get practice_theme_url(@practice_theme)

    assert_response :success
    assert_select "h1", "接客練習"
    assert_select "h2", "練習テーマ：家電の提案販売"
    assert_select "h3", "👤 お客様像"
    assert_select "h3", "🎯 今回の接客ポイント"
    assert_select "p", /冷蔵庫売り場に来店している30代くらいの男女/
    assert_select "p", /お客様へ明るく声掛けをする/
    assert_select "p", /現在の利用状況を確認する/
    assert_select "p", /お客様に合ったサービスを提案する/
    assert_select "#recording-status", "停止中"
    assert_select "#start-recording", "録音開始"
    assert_select "#stop-recording", "録音停止"
    assert_select "#start-recording:not([disabled])"
    assert_select "#stop-recording[disabled]"
  end

  test "録音データから声量を分析して保存できる" do
    audio_file = fixture_file_upload(
      "test_volume.webm",
      "audio/webm"
    )

    transcription_service = Minitest::Mock.new
    transcription_service.expect(
      :call,
      { "text" => "こんにちは今日はいい天気ですね" }
    )

    ai_comment_service = Minitest::Mock.new
    ai_comment_service.expect(
      :call,
      "テスト用のAIコメントです。"
    )

    GroqTranscriptionService.stub(
      :new,
      ->(_audio) { transcription_service }
    ) do
      AiCommentService.stub(
        :new,
        ->(_analysis) { ai_comment_service }
      ) do
        assert_difference("Practice.count", 1) do
          assert_difference("Analysis.count", 1) do
            post create_practice_practice_theme_url(@practice_theme),
              params: {
                audio: audio_file,
                duration: 1.0
              }
          end
        end
      end
    end

    assert_response :success

    analysis = Analysis.order(:created_at).last

    assert_not_nil analysis
    assert_equal @user, analysis.practice.user
    assert_equal @practice_theme, analysis.practice.practice_theme
    assert_in_delta(-21.1, analysis.volume, 0.5)

    transcription_service.verify
    ai_comment_service.verify
  end

  test "録音データからフィラーを分析して保存できる" do
    audio_file = fixture_file_upload(
      "test_volume.webm",
      "audio/webm"
    )

    transcription_service = Minitest::Mock.new
    transcription_service.expect(
      :call,
      { "text" => "えー今日はですねあのーおすすめの商品ですえっとこちらになります" }
    )

    ai_comment_service = Minitest::Mock.new
    ai_comment_service.expect(
      :call,
      "テスト用のAIコメントです。"
    )

    GroqTranscriptionService.stub(
      :new,
      ->(_audio) { transcription_service }
    ) do
      AiCommentService.stub(
        :new,
        ->(_analysis) { ai_comment_service }
      ) do
        assert_difference("Practice.count", 1) do
          assert_difference("Analysis.count", 1) do
            post create_practice_practice_theme_url(@practice_theme),
              params: {
                audio: audio_file,
                duration: 60.0
              }
          end
        end
      end
    end

    assert_response :success

    analysis = Analysis.order(:created_at).last

    assert_not_nil analysis
    assert_equal 3, analysis.filler_count
    assert_equal 60, analysis.filler_score

    transcription_service.verify
    ai_comment_service.verify
  end

  test "分析結果をもとにAIコメントを生成して保存できる" do
    audio_file = fixture_file_upload(
      "test_volume.webm",
      "audio/webm"
    )

    transcription_service = Minitest::Mock.new
    transcription_service.expect(
      :call,
      { "text" => "こんにちは今日はいい天気ですね" }
    )

    ai_comment_service = Minitest::Mock.new
    ai_comment_service.expect(
      :call,
      "フィラーを減らすため、一呼吸おいてから話す練習をしましょう。"
    )

    GroqTranscriptionService.stub(
      :new,
      ->(_audio) { transcription_service }
    ) do
      AiCommentService.stub(
        :new,
        ->(_analysis) { ai_comment_service }
      ) do
        assert_difference("Practice.count", 1) do
          assert_difference("Analysis.count", 1) do
            post create_practice_practice_theme_url(@practice_theme),
              params: {
                audio: audio_file,
                duration: 1.0
              }
          end
        end
      end
    end

    assert_response :success

    analysis = Analysis.order(:created_at).last

    assert_not_nil analysis
    assert_equal(
      "フィラーを減らすため、一呼吸おいてから話す練習をしましょう。",
      analysis.ai_comment
    )

    transcription_service.verify
    ai_comment_service.verify
  end
end
