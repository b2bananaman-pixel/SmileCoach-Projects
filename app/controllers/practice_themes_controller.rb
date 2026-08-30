class PracticeThemesController < ApplicationController
  before_action :authenticate_user!

  def index
    @practice_themes = PracticeTheme.all
  end

  def show
    @practice_theme = PracticeTheme.find(params[:id])
  end

  def create_practice
    practice_theme = PracticeTheme.find(params[:id])

    practice = Practice.new(
      user: current_user,
      practice_theme: practice_theme,
      duration: params[:duration]
    )

    practice.audio.attach(params[:audio])
    practice.save!

    transcription_result = GroqTranscriptionService.new(practice.audio).call
    practice.update!(transcription: transcription_result["text"])

    volume = VolumeAnalysis.new(practice.audio).volume

    speech_analysis = SpeechAnalysis.new(
      transcription: practice.transcription,
      duration: practice.duration
    )

    score_analysis = ScoreAnalysis.new(
      speech_speed: speech_analysis.speech_speed,
      volume: volume,
      filler_score: speech_analysis.filler_score
    )

    practice.create_analysis!(
      volume: volume,
      volume_score: score_analysis.volume_score,
      speech_speed: speech_analysis.speech_speed,
      speech_speed_score: score_analysis.speech_speed_score,
      filler_count: speech_analysis.filler_count,
      total_score: score_analysis.total_score,
      filler_score: speech_analysis.filler_score
    )
    analysis = practice.analysis
    ai_comment = AiCommentService.new(analysis).call
    analysis.update!(ai_comment: ai_comment)

    render json: {
      success: true,
      practice_id: practice.id,
      analysis_id: practice.analysis.id,
      transcription: practice.transcription
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      errors: e.record.errors.full_messages
    }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("文字起こしに失敗しました: #{e.message}")

    render json: {
      success: false,
      errors: [ "文字起こしに失敗しました" ]
    }, status: :unprocessable_entity
  end
end
