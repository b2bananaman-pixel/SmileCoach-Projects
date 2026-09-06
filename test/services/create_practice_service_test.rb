require "test_helper"

class CreatePracticeServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @practice_theme = PracticeTheme.create!(
      name: "家電の提案販売",
      description: "テスト用の練習テーマ"
    )
  end

  test "練習を作成して分析結果とAIコメントを保存できる" do
    audio_file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_volume.webm"),
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
        service = CreatePracticeService.new(
          user: @user,
          practice_theme: @practice_theme,
          audio: audio_file,
          duration: 1.0
        )

        practice = service.call

        assert_not_nil practice
        assert_equal @user, practice.user
        assert_equal @practice_theme, practice.practice_theme
        assert_equal "こんにちは今日はいい天気ですね", practice.transcription

        analysis = practice.analysis

        assert_not_nil analysis
        assert_in_delta(-21.1, analysis.volume, 0.5)
        assert_equal(
          "テスト用のAIコメントです。",
          analysis.ai_comment
        )
      end
    end

    transcription_service.verify
    ai_comment_service.verify
  end
end
