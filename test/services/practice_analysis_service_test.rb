require "test_helper"

class PracticeAnalysisServiceTest < ActiveSupport::TestCase
  setup do
    @practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      duration: 1.0,
      transcription: "こんにちは今日はいい天気ですね"
    )

    @practice.audio.attach(
      io: File.open(Rails.root.join("test/fixtures/files/test_volume.webm")),
      filename: "test_volume.webm",
      content_type: "audio/webm"
    )
  end

  test "保存済みの文字起こしと音声から分析結果とAIコメントを保存できる" do
    ai_comment_service = Minitest::Mock.new
    ai_comment_service.expect(
      :call,
      "テスト用のAIコメントです。"
    )

    analysis = nil

    AiCommentService.stub(
      :new,
      ->(_analysis) { ai_comment_service }
    ) do
      analysis = PracticeAnalysisService.new(@practice).call
    end

    expected_speech = SpeechAnalysis.new(
      transcription: "こんにちは今日はいい天気ですね",
      duration: 1.0,
      speech_duration: 1.0
    )

    expected_score = ScoreAnalysis.new(
      speech_speed: expected_speech.speech_speed,
      volume: analysis.volume,
      filler_score: expected_speech.filler_score
    )

    assert analysis.persisted?
    assert_equal @practice, analysis.practice
    assert_in_delta(-21.1, analysis.volume, 0.5)
    assert_equal expected_score.volume_score, analysis.volume_score
    assert_in_delta expected_speech.speech_speed, analysis.speech_speed, 0.001
    assert_equal expected_score.speech_speed_score, analysis.speech_speed_score
    assert_equal 0, analysis.filler_count
    assert_equal 100, analysis.filler_score
    assert_equal expected_score.total_score, analysis.total_score
    assert_nil analysis.smile_score
    assert_equal "テスト用のAIコメントです。", analysis.reload.ai_comment

    ai_comment_service.verify
  end

  test "Groqで文字起こしせずPracticeに保存済みの文字起こしを使う" do
    @practice.update!(transcription: "えーと、あのご案内します")

    transcription_service = Object.new

    def transcription_service.call
      raise "文字起こしは呼び出さないこと"
    end

    analysis = nil

    GroqTranscriptionService.stub(
      :new,
      ->(_audio) { transcription_service }
    ) do
      AiCommentService.stub(
        :new,
        ->(_analysis) { Struct.new(:call).new("コメント") }
      ) do
        analysis = PracticeAnalysisService.new(@practice).call
      end
    end

    assert_equal 2, analysis.filler_count
    assert_equal "えーと、あのご案内します", @practice.reload.transcription
  end

  test "AIコメント生成に失敗しても分析結果を保存し例外クラスだけをログに出す" do
    ai_comment_service = Object.new

    def ai_comment_service.call
      raise "Groq API request failed: test-api-key"
    end

    logged_message = nil
    analysis = nil

    AiCommentService.stub(
      :new,
      ->(_analysis) { ai_comment_service }
    ) do
      Rails.logger.stub(
        :error,
        ->(message) { logged_message = message }
      ) do
        analysis = PracticeAnalysisService.new(@practice).call
      end
    end

    assert analysis.persisted?
    assert_nil analysis.reload.ai_comment

    assert_includes logged_message, "AIコメント生成に失敗しました"
    assert_includes logged_message, "RuntimeError"
    refute_includes logged_message, "test-api-key"
  end

  test "音声が添付されていない場合も声量0として分析結果を保存できる" do
    practice = Practice.create!(
      user: users(:one),
      practice_theme: practice_themes(:one),
      duration: 1.0,
      transcription: "こんにちは"
    )

    analysis = nil

    AiCommentService.stub(
      :new,
      ->(_analysis) { Struct.new(:call).new("コメント") }
    ) do
      analysis = PracticeAnalysisService.new(practice).call
    end

    assert analysis.persisted?
    assert_equal 0.0, analysis.volume
    assert_equal 0, analysis.volume_score
  end

  test "文字起こしが空で録音時間が0の場合も例外にならず0点で保存する" do
    @practice.update!(transcription: "", duration: 0.0)

    analysis = nil

    AiCommentService.stub(
      :new,
      ->(_analysis) { Struct.new(:call).new("コメント") }
    ) do
      analysis = PracticeAnalysisService.new(@practice).call
    end

    assert analysis.persisted?
    assert_equal 0.0, analysis.speech_speed
    assert_equal 0, analysis.speech_speed_score
    assert_equal 0, analysis.filler_count
    assert_equal 0, analysis.filler_score
  end

  test "分析処理の各工程の処理時間をログに出す" do
    logged_messages = []

    AiCommentService.stub(
      :new,
      ->(_analysis) { Struct.new(:call).new("コメント") }
    ) do
      Rails.logger.stub(
        :info,
        ->(message = nil) { logged_messages << message }
      ) do
        PracticeAnalysisService.new(@practice).call
      end
    end

    %w[
      声量分析
      発話時間分析
      話速・フィラー分析
      スコア計算
      Analysis保存
      AIコメント生成
      AIコメント保存
    ].each do |label|
      assert(
        logged_messages.any? { |message| message.to_s.start_with?("[AnalysisPerformance] #{label}: ") },
        "#{label}の処理時間がログに出力されていません"
      )
    end
  end
end
