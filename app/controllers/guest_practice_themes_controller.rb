class GuestPracticeThemesController < ApplicationController
  def index
    @practice_themes = PracticeTheme.all
  end

  def show
    @practice_theme = PracticeTheme.find(params[:id])
  end

  def create_practice
    result = GuestAudioAnalysisService.new(
      audio: params[:audio],
      duration: params[:duration]
    ).call

    render json: {
      success: true,
      total_score: result.total_score,
      speech_speed: result.speech_speed,
      speech_speed_score: result.speech_speed_score,
      filler_count: result.filler_count,
      filler_score: result.filler_score,
      volume: result.volume,
      volume_score: result.volume_score,
      ai_comment: result.ai_comment
    }
  rescue StandardError => e
    Rails.logger.error(
      "ゲストの音声分析に失敗しました: #{e.class} - #{e.message}"
    )

    render json: {
      success: false,
      errors: [ "音声分析に失敗しました" ]
    }, status: :unprocessable_entity
  end
end
