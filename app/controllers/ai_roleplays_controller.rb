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

  # 録画の転送先（ストレージの期限付きURL）の有効期限
  VIDEO_URL_EXPIRES_IN = 30.minutes

  # 録画の削除結果のメッセージ
  VIDEO_DELETED_MESSAGE = "録画動画を削除しました。評価結果と会話履歴は引き続き確認できます。".freeze
  VIDEO_ALREADY_DELETED_MESSAGE = "録画動画はすでに削除されています。".freeze
  VIDEO_DELETE_FAILED_MESSAGE = "録画動画を削除できませんでした。時間をおいて再度お試しください。".freeze

  # ローカルDisk保存でも録画の期限付きURLを生成できるように、URL生成用のホスト情報を設定する
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :set_roleplay_product, only: [ :show ]

  # 商材を起点にAIロープレを開始する（GET /products/:product_id/ai_roleplay）
  #
  # 開始時点の商材情報を暗号化したトークンを画面に渡し、会話の返答生成と終了時の保存で受け取る。
  def show
    @product_snapshot_token = AiRoleplayProductSnapshotToken.generate(
      user: current_user,
      product: @product
    )
  end

  def evaluation
    @ai_roleplay_session = current_user.ai_roleplay_sessions
                                       .with_attached_video
                                       .includes(:practice_theme, :ai_roleplay_evaluation, practice: :analysis)
                                       .find(params[:id])
    @ai_roleplay_evaluation = @ai_roleplay_session.ai_roleplay_evaluation
    set_practice_selection_link

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

  # 本人のAIロープレの録画だけを削除する（DELETE /ai_roleplays/:id/video）
  #
  # 評価・会話・話し方の分析などの学習記録は残す。録画がない（削除済み）場合も500にせず、評価画面へ戻す。
  def destroy_video
    # 他のユーザーのAIロープレや存在しないIDは404とする
    ai_roleplay_session = current_user.ai_roleplay_sessions.find(params[:id])

    redirect_to evaluation_ai_roleplay_path(ai_roleplay_session),
                **delete_video_flash(ai_roleplay_session),
                status: :see_other
  end

  # 商材のトークンは必須とし、商材を選択していない新規のAIロープレは保存しない
  #
  # 商材を起点としたAIロープレでは練習テーマを使わないため、練習テーマは保存しない（送られても使用しない）。
  def create
    conversation_history = parsed_conversation_history
    roleplay_product = verified_roleplay_product

    ai_roleplay_session = current_user.ai_roleplay_sessions.new(
      product: roleplay_product.fetch(:product),
      product_snapshot: roleplay_product.fetch(:product_snapshot),
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

  # AIロープレ画面で発行したトークンを検証し、開始時点の商材情報で返答を生成する（トークンは必須）
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

    transcription = AiRoleplayTranscriptionService.new(
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

  # 録画を削除し、結果に応じたメッセージを返す
  def delete_video_flash(ai_roleplay_session)
    result = AiRoleplayVideoDeletionService.new(ai_roleplay_session: ai_roleplay_session).call

    { notice: result.deleted? ? VIDEO_DELETED_MESSAGE : VIDEO_ALREADY_DELETED_MESSAGE }
  rescue StandardError => e
    # 例外メッセージにストレージのキーやURLが含まれる可能性があるため、IDとクラス名のみ記録する
    Rails.logger.error(
      "[AiRoleplaysController#destroy_video] 録画を削除できませんでした: ai_roleplay_session_id=#{ai_roleplay_session.id} (#{e.class})"
    )

    { alert: VIDEO_DELETE_FAILED_MESSAGE }
  end

  # 評価画面から練習を選び直す導線
  #
  # 練習したカテゴリが現在も有効な場合はそのカテゴリの商材選択へ、それ以外（無効・商材のない過去のセッション）はカテゴリ選択へ戻す。
  def set_practice_selection_link
    category_id = @ai_roleplay_session.product_snapshot&.dig("category", "id")

    if category_id.is_a?(Integer) && ProductCategory.active.exists?(id: category_id)
      @practice_selection_label = "商材選択へ戻る"
      @practice_selection_path = practice_category_path(category_id)
    else
      @practice_selection_label = "カテゴリ選択へ戻る"
      @practice_selection_path = practice_categories_path
    end
  end

  # 存在しない・非公開・無効カテゴリの商材と、不正な形式の商材IDは404とする
  #
  # 管理者も一般ユーザーと同じ条件で、AIロープレで利用可能な商材だけを選択できる。
  def set_roleplay_product
    product_id = params[:product_id]

    raise ActiveRecord::RecordNotFound unless product_id.is_a?(String) && product_id.match?(PRODUCT_ID_FORMAT)

    @product = Product.available_for_roleplay.includes(:product_category).find(product_id)
  end

  # 保存時の商材は、AIロープレ画面で発行したトークンの内容だけを使い、
  # ブラウザから送られたproduct_id・product_snapshotは使用しない
  #
  # 開始時点で利用可能だった商材は、練習中に非公開・カテゴリ無効になっても保存できるよう、
  # 保存時は公開状態・カテゴリの状態を確認せず、トークンの正当性と商材の存在だけを確認する。
  # トークンがない場合も、不正なトークンとして扱う（商材を選択していないAIロープレは保存しない）
  def verified_roleplay_product
    result = AiRoleplayProductSnapshotToken.verify!(
      params[:product_snapshot_token],
      user: current_user
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
  # トークンがない場合も、不正なトークンとして扱う。
  def verified_respond_product_snapshot
    AiRoleplayProductSnapshotToken.verify!(
      params[:product_snapshot_token],
      user: current_user
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
