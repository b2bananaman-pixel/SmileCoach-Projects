class AiRoleplaysController < ApplicationController
  before_action :authenticate_user!

  def synthesize
    text = params.require(:text)

    audio = GoogleTextToSpeechService.new(text: text).call

    send_data(
      audio,
      type: "audio/mpeg",
      disposition: "inline",
      filename: "ai_roleplay_response.mp3"
    )
  rescue ActionController::ParameterMissing, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error(
      "[AiRoleplaysController#synthesize] #{e.class}: #{e.message}"
    )

    render json: {
      error: "音声の生成に失敗しました"
    }, status: :bad_gateway
  end

  def respond
    clerk_message = params.require(:clerk_message)

    ai_response = AiRoleplayResponseService.new(
      clerk_message: clerk_message
    ).call

    render json: ai_response
  rescue ActionController::ParameterMissing, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error(
      "[AiRoleplaysController#respond] #{e.class}: #{e.message}"
    )

    render json: {
      error: "AI顧客の返答生成に失敗しました"
    }, status: :bad_gateway
  end

  def transcribe
    audio = params.require(:audio)

    transcription = GuestTranscriptionService.new(
      audio.tempfile
    ).call

    render json: {
      transcription: transcription
    }
  rescue ActionController::ParameterMissing, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error(
      "[AiRoleplaysController#transcribe] #{e.class}: #{e.message}"
    )

    render json: {
      error: "音声の文字起こしに失敗しました"
    }, status: :bad_gateway
  end
end
