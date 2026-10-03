class AiRoleplaysController < ApplicationController
  before_action :authenticate_user!
  before_action :set_practice_theme, only: [ :show ]

  def show
  end

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
    conversation_history = parsed_conversation_history

    ai_response = AiRoleplayResponseService.new(
      clerk_message: clerk_message,
      conversation_history: conversation_history
    ).call

    render json: ai_response
  rescue ActionController::ParameterMissing, ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue JSON::ParserError => e
    Rails.logger.warn(
      "[AiRoleplaysController#respond] Invalid conversation history: #{e.message}"
    )

    render json: {
      error: "会話履歴の形式が不正です"
    }, status: :unprocessable_entity
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

  private

  def set_practice_theme
    @practice_theme = PracticeTheme.find(params[:id])
  end

  def parsed_conversation_history
    raw_history = params[:conversation_history]

    return [] if raw_history.blank?

    history =
      case raw_history
      when String
        JSON.parse(raw_history)
      when Array
        raw_history
      else
        raise ArgumentError, "conversation_history is invalid"
      end

    unless history.is_a?(Array)
      raise ArgumentError, "conversation_history must be an array"
    end

    history
  end
end
