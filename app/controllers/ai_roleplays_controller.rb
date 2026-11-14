class AiRoleplaysController < ApplicationController
  # 発話音声として受け付ける形式（MediaRecorderの音声録音形式）
  CLERK_AUDIO_CONTENT_TYPE = "audio/webm".freeze

  class InvalidClerkAudioError < StandardError; end

  # 商材情報のトークンが指す商材が存在しない場合のエラー
  class RoleplayProductNotFoundError < StandardError; end

  # AIロープレ画面で受け付ける商材IDの形式（正の整数）
  #
  # "1abc" のような値も型変換で1として検索されてしまうため、文字列の形式を先に確認する。
  PRODUCT_ID_FORMAT = /\A[1-9][0-9]{0,18}\z/

  # 会話の返答生成で受け付ける練習テーマIDの形式（正の整数）
  PRACTICE_THEME_ID_FORMAT = /\A[1-9][0-9]{0,18}\z/

  # 会話の返答生成で、商材のトークンと一緒に送られた練習テーマIDがない・形式が不正な場合のエラー
  class InvalidPracticeThemeIdError < StandardError; end

  # 録画の転送先（ストレージの期限付きURL）の有効期限
  VIDEO_URL_EXPIRES_IN = 30.minutes

  # ローカルDisk保存でも録画の期限付きURLを生成できるように、URL生成用のホスト情報を設定する
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :set_practice_theme, only: [ :show ]
  before_action :set_roleplay_product, only: [ :show ]

  # 商材を選択した場合は、開始時点の商材情報を暗号化したトークンを画面に渡し、終了時の保存で受け取る
  def show
    return if @product.nil?

    @product_snapshot_token = AiRoleplayProductSnapshotToken.generate(
      user: current_user,
      practice_theme: @practice_theme,
      product: @product
    )
  end

  def evaluation
    @ai_roleplay_session = current_user.ai_roleplay_sessions
                                       .with_attached_video
                                       .includes(:practice_theme, :ai_roleplay_evaluation, practice: :analysis)
                                       .find(params[:id])
    @ai_roleplay_evaluation = @ai_roleplay_session.ai_roleplay_evaluation

    # 話し方の分析は接客内容の評価とは別の参考評価として表示する（過去のAIロープレには存在しない）
    @voice_analysis = @ai_roleplay_session.practice&.analysis
  end

  # 本人のAIロープレであることを確認してから、録画の期限付きURLへ転送する
  #
  # Active Storageの公開URL（期限なし）を画面に出さないため、評価画面の動画はこのURLから読み込む。
  # 転送先のURLは有効期限内であれば誰でも開けるため、ブラウザに保存させず、ログにも出さない。
  def video
    ai_roleplay_session = current_user.ai_roleplay_sessions.with_attached_video.find(params[:id])

    return head :not_found unless ai_roleplay_session.video.attached?

    no_store

    # redirect_toは転送先URLをログに出力するため、Locationヘッダーを直接設定する
    head :found,
         location: ai_roleplay_session.video.url(expires_in: VIDEO_URL_EXPIRES_IN, disposition: :inline),
         "Referrer-Policy" => "no-referrer"
  end

  def create
    conversation_history = parsed_conversation_history
    practice_theme = PracticeTheme.find(params.require(:practice_theme_id))
    roleplay_product = verified_roleplay_product(practice_theme)

    ai_roleplay_session = current_user.ai_roleplay_sessions.new(
      practice_theme: practice_theme,
      product: roleplay_product&.fetch(:product),
      product_snapshot: roleplay_product&.fetch(:product_snapshot),
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
  rescue AiRoleplayProductSnapshotToken::InvalidTokenError => e
    Rails.logger.warn(
      "[AiRoleplaysController#create] Invalid product snapshot token"
    )

    render json: {
      error: e.message
    }, status: :unprocessable_entity
  rescue RoleplayProductNotFoundError
    Rails.logger.warn(
      "[AiRoleplaysController#create] Roleplay product not found"
    )

    render json: {
      error: "選択した商材が見つかりません"
    }, status: :not_found
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

  # 商材を選択した場合は、AIロープレ画面で発行したトークンを検証し、開始時点の商材情報で返答を生成する
  def respond
    clerk_message = params.require(:clerk_message)
    conversation_history = parsed_conversation_history
    product_snapshot = verified_respond_product_snapshot

    ai_response = AiRoleplayResponseService.new(
      clerk_message: clerk_message,
      conversation_history: conversation_history,
      product_snapshot: product_snapshot
    ).call

    render json: ai_response
  rescue AiRoleplayProductSnapshotToken::InvalidTokenError => e
    Rails.logger.warn(
      "[AiRoleplaysController#respond] Invalid product snapshot token"
    )

    render json: {
      error: e.message
    }, status: :unprocessable_entity
  rescue InvalidPracticeThemeIdError
    Rails.logger.warn(
      "[AiRoleplaysController#respond] Invalid practice theme id"
    )

    render json: {
      error: "練習テーマの指定が不正です"
    }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn(
      "[AiRoleplaysController#respond] Practice theme not found"
    )

    render json: {
      error: "練習テーマが見つかりません"
    }, status: :not_found
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

  # 商材IDの指定がない・空文字の場合は商材未選択とし、従来どおりAIロープレを開始する
  #
  # 存在しない・非公開・無効カテゴリの商材と、不正な形式の商材IDは404とする。
  # 管理者も一般ユーザーと同じ条件で、AIロープレで利用可能な商材だけを選択できる。
  def set_roleplay_product
    product_id = params[:product_id]

    return if product_id.nil? || product_id == ""

    raise ActiveRecord::RecordNotFound unless product_id.is_a?(String) && product_id.match?(PRODUCT_ID_FORMAT)

    @product = Product.available_for_roleplay.includes(:product_category).find(product_id)
  end

  # 保存時の商材は、AIロープレ画面で発行したトークンの内容だけを使い、
  # ブラウザから送られたproduct_id・product_snapshotは使用しない
  #
  # 開始時点で利用可能だった商材は、練習中に非公開・カテゴリ無効になっても保存できるよう、
  # 保存時は公開状態・カテゴリの状態を確認せず、トークンの正当性と商材の存在だけを確認する。
  def verified_roleplay_product(practice_theme)
    token = params[:product_snapshot_token]

    return if token.nil? || token == ""

    result = AiRoleplayProductSnapshotToken.verify!(
      token,
      user: current_user,
      practice_theme: practice_theme
    )

    product = Product.find_by(id: result.product_id)
    raise RoleplayProductNotFoundError if product.nil?

    { product: product, product_snapshot: result.product_snapshot }
  end

  # 会話の返答生成で使う商材情報は、AIロープレ画面で発行したトークンの内容だけを使う
  #
  # ブラウザから送られたproduct_id・product_snapshotは使用しない。
  # 開始時点の商材情報で会話を続けるため、会話のたびに商材をDBから取得しない。
  # そのため、練習中に商材が編集・非公開・カテゴリ無効になっても、開始時点の内容で返答を生成する。
  def verified_respond_product_snapshot
    token = params[:product_snapshot_token]

    return if token.nil? || token == ""

    practice_theme_id = params[:practice_theme_id]

    unless practice_theme_id.is_a?(String) && practice_theme_id.match?(PRACTICE_THEME_ID_FORMAT)
      raise InvalidPracticeThemeIdError
    end

    AiRoleplayProductSnapshotToken.verify!(
      token,
      user: current_user,
      practice_theme: PracticeTheme.find(practice_theme_id)
    ).product_snapshot
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
