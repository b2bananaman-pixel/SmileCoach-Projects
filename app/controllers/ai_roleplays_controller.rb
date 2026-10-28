class AiRoleplaysController < ApplicationController
  # 発話音声として受け付ける形式（MediaRecorderの音声録音形式）
  CLERK_AUDIO_CONTENT_TYPE = "audio/webm".freeze

  class InvalidClerkAudioError < StandardError; end

  before_action :authenticate_user!
  before_action :set_practice_theme, only: [ :show ]

  def show
  end

  def evaluation
    @ai_roleplay_session = current_user.ai_roleplay_sessions
                                       .includes(:practice_theme, :ai_roleplay_evaluation, practice: :analysis)
                                       .find(params[:id])
    @ai_roleplay_evaluation = @ai_roleplay_session.ai_roleplay_evaluation

    # 話し方の分析は接客内容の評価とは別の参考評価として表示する（過去のAIロープレには存在しない）
    @voice_analysis = @ai_roleplay_session.practice&.analysis
  end

  def create
    conversation_history = parsed_conversation_history
    practice_theme = PracticeTheme.find(params.require(:practice_theme_id))

    ai_roleplay_session = current_user.ai_roleplay_sessions.new(
      practice_theme: practice_theme,
      duration: params[:duration],
      end_reason: params[:end_reason],
      started_at: params[:started_at],
      ended_at: params[:ended_at]
    )

    ai_roleplay_session.video.attach(params[:video]) if params[:video].present?

    AiRoleplaySession.transaction do
      ai_roleplay_session.save!

      conversation_history.each do |message|
        ai_roleplay_session.ai_roleplay_messages.create!(
          role: message["role"],
          content: message["content"]
        )
      end
    end

    evaluate_ai_roleplay(ai_roleplay_session)

    # 発話音声のアップロードはコミット後に行われるため、保存のトランザクションが完了してから分析する
    analyze_clerk_voice(ai_roleplay_session)

    render json: {
      id: ai_roleplay_session.id
    }, status: :created
  rescue JSON::ParserError => e
    Rails.logger.warn(
      "[AiRoleplaysController#create] Invalid conversation history: #{e.message}"
    )

    render json: {
      error: "会話履歴の形式が不正です"
    }, status: :unprocessable_entity
  rescue ActionController::ParameterMissing,
         ArgumentError,
         ActiveRecord::RecordInvalid => e
    Rails.logger.warn(
      "[AiRoleplaysController#create] #{e.class}: #{e.message}"
    )

    render json: {
      error: e.message
    }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error(
      "[AiRoleplaysController#create] #{e.class}: #{e.message}"
    )

    render json: {
      error: "AIロープレ記録の保存に失敗しました"
    }, status: :internal_server_error
  end

  def synthesize
    text = params.require(:text)

    # 画面表示・会話履歴とは別に、音声合成用のテキストだけを読み上げやすい表記へ変換する
    speech_text = SpeechTextNormalizer.new(text).call

    audio = GoogleTextToSpeechService.new(text: speech_text).call

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

  # 評価に失敗してもセッション保存は成功扱いとするため、例外はここで処理する
  def evaluate_ai_roleplay(ai_roleplay_session)
    AiRoleplayEvaluationService.new(ai_roleplay_session).call
  rescue AiRoleplayEvaluationService::InvalidResponseError => e
    # 検証エラーのメッセージは固定文とキー名のみで構成され、会話内容や応答本文を含まない
    Rails.logger.error(
      "[AiRoleplaysController#create] AI roleplay evaluation failed: #{e.class} (#{e.message})"
    )
  rescue StandardError => e
    # 例外メッセージに会話内容やレスポンス本文が含まれる可能性があるため、クラス名のみ記録する
    Rails.logger.error(
      "[AiRoleplaysController#create] AI roleplay evaluation failed: #{e.class}"
    )
  end

  # 話し方の音声分析は接客内容の評価とは別の補助評価のため、失敗してもセッション保存は成功扱いとする
  def analyze_clerk_voice(ai_roleplay_session)
    AiRoleplayVoiceAnalysisService.new(
      ai_roleplay_session: ai_roleplay_session,
      audio_files: clerk_audio_turns
    ).call
  rescue InvalidClerkAudioError, ClerkAudioConcatenator::InvalidInputError => e
    # 入力検証のメッセージは固定文と件数・上限値のみで構成され、発話内容やファイル名を含まない
    Rails.logger.warn(
      "[AiRoleplaysController#create] AI roleplay voice analysis skipped: #{e.class} (#{e.message})"
    )
  rescue StandardError => e
    # ffmpegや分析処理のエラー内容は記録せず、クラス名のみ記録する
    Rails.logger.error(
      "[AiRoleplaysController#create] AI roleplay voice analysis failed: #{e.class}"
    )
  end

  # 件数・1件あたりのサイズ・合計サイズの上限は ClerkAudioConcatenator で、
  # 会話履歴の発言数との一致は AiRoleplayVoiceAnalysisService で確認する
  def clerk_audio_turns
    turns = params[:clerk_audio_turns]

    return [] if turns.nil?

    raise InvalidClerkAudioError, "発話音声の形式が不正です" unless turns.is_a?(Array)

    if turns.size > ClerkAudioConcatenator::MAX_FILES
      raise InvalidClerkAudioError,
            "発話音声の数が多すぎます（上限#{ClerkAudioConcatenator::MAX_FILES}件）"
    end

    turns.each_with_index do |turn, index|
      unless turn.is_a?(ActionDispatch::Http::UploadedFile)
        raise InvalidClerkAudioError, "#{index + 1}件目の発話音声がファイルではありません"
      end

      unless clerk_audio_content_type?(turn.content_type)
        raise InvalidClerkAudioError, "#{index + 1}件目の発話音声の形式が不正です"
      end
    end

    turns
  end

  # MediaRecorderは "audio/webm;codecs=opus" のようにパラメータ付きで送るため、種類だけを比較する
  # 申告された形式は改ざんできるため、中身が正しいWebMかどうかは結合時にffmpegで確認する
  def clerk_audio_content_type?(content_type)
    content_type.to_s.split(";").first.to_s.strip.casecmp?(CLERK_AUDIO_CONTENT_TYPE)
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
