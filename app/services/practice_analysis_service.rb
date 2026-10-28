# 保存済みのPracticeの音声・文字起こし・録音時間から話し方を分析し、Analysisを作成する
#
# 文字起こしはpractice.transcriptionを使用する。
# 通常録画ではGroqで文字起こしした結果を、AIロープレでは会話中に取得した利用者の発言を
# 事前にPracticeへ保存してから呼び出す。
class PracticeAnalysisService
  include AnalysisPerformanceMeasurement

  def initialize(practice)
    @practice = practice
  end

  def call
    volume = measure("声量分析") do
      VolumeAnalysis.new(@practice.audio).volume
    end

    speech_duration = measure("発話時間分析") do
      SpeechDurationAnalysis.new(
        @practice.audio,
        duration: @practice.duration
      ).speech_duration
    end

    speech_speed = nil
    filler_count = nil
    filler_score = nil

    measure("話速・フィラー分析") do
      speech_analysis = SpeechAnalysis.new(
        transcription: @practice.transcription,
        duration: @practice.duration,
        speech_duration: speech_duration
      )

      speech_speed = speech_analysis.speech_speed
      filler_count = speech_analysis.filler_count
      filler_score = speech_analysis.filler_score
    end

    score_analysis = measure("スコア計算") do
      ScoreAnalysis.new(
        speech_speed: speech_speed,
        volume: volume,
        filler_score: filler_score
      )
    end

    analysis = measure("Analysis保存") do
      @practice.create_analysis!(
        volume: volume,
        volume_score: score_analysis.volume_score,
        speech_speed: speech_speed,
        speech_speed_score: score_analysis.speech_speed_score,
        filler_count: filler_count,
        total_score: score_analysis.total_score,
        filler_score: filler_score
      )
    end

    generate_ai_comment(analysis)

    analysis
  end

  private

  # AIコメントの生成に失敗しても分析結果は保存済みとして扱う
  def generate_ai_comment(analysis)
    ai_comment = measure("AIコメント生成") do
      AiCommentService.new(analysis).call
    end

    measure("AIコメント保存") do
      analysis.update!(ai_comment: ai_comment)
    end
  rescue StandardError => e
    Rails.logger.error(
      "AIコメント生成に失敗しました: #{e.class}"
    )
  end
end
