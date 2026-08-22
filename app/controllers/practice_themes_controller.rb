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

    render json: {
      success: true,
      practice_id: practice.id,
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
