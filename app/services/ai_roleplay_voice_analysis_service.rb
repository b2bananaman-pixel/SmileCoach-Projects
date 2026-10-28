# AIロープレ中に録音した利用者（店員役）の発話音声から、話速・フィラー・声量を分析する
#
# - 音声は発話ごとに録音した利用者のマイク音声だけを受け取り、AI顧客の読み上げ音声は扱わない
# - 文字起こしは会話中に保存した利用者の発言（role: "user"）を使い、Groqで再度文字起こししない
# - 発話音声は、会話履歴の利用者の発言と同じ順番・同じ件数で受け取る
#
# 分析した場合は作成したPracticeを、分析を行わなかった場合はnilを返す。
# 音声の結合や分析に失敗した場合は、作成途中のPracticeと音声を削除してから例外を再送出する。
#
# ActiveStorageの音声アップロードは保存のコミット後に行われるため、
# 外側でトランザクションを開いた状態で呼び出さないこと。
class AiRoleplayVoiceAnalysisService
  include AnalysisPerformanceMeasurement

  AUDIO_FILENAME = "ai_roleplay_clerk_audio.webm".freeze

  def initialize(ai_roleplay_session:, audio_files:)
    @ai_roleplay_session = ai_roleplay_session
    @audio_files = Array(audio_files)
  end

  def call
    clerk_messages = @ai_roleplay_session.ai_roleplay_messages
                                         .where(role: "user")
                                         .order(:id)
                                         .pluck(:content)

    return skip("利用者の発言がありません") if clerk_messages.empty?
    return skip("発話音声がありません") if @audio_files.empty?

    # 発言と音声の対応がずれると誤った分析結果になるため、件数が一致しない場合は分析しない
    if clerk_messages.size != @audio_files.size
      return skip(
        "発言数（#{clerk_messages.size}件）と発話音声数（#{@audio_files.size}件）が一致しません"
      )
    end

    return skip("音声分析済みです") if already_analyzed?

    total_started_at = monotonic_time
    practice = nil

    # 結合した一時ファイルが存在する間に、Practiceの保存と音声のアップロードを完了させる
    ClerkAudioConcatenator.new(@audio_files).call do |result|
      practice = measure("音声分析用Practice保存") do
        create_practice(clerk_messages, result)
      end
    end

    PracticeAnalysisService.new(practice).call

    log_duration(
      "AIロープレ音声分析合計",
      monotonic_time - total_started_at
    )

    practice
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
    # 同じセッションの分析が同時に実行された場合は、先に保存された結果を残す
    return skip("音声分析済みです") if duplicate_practice_error?(e, practice)

    discard(practice)
    raise
  rescue StandardError
    discard(practice)
    raise
  end

  private

  def already_analyzed?
    Practice.exists?(ai_roleplay_session_id: @ai_roleplay_session.id)
  end

  # Practiceの保存前に発生した、同じセッションへの重複登録エラーだけを重複実行として扱う
  def duplicate_practice_error?(error, practice)
    return false if practice&.persisted?
    return already_analyzed? if error.is_a?(ActiveRecord::RecordNotUnique)

    error.record.is_a?(Practice) &&
      error.record.errors.of_kind?(:ai_roleplay_session_id, :taken)
  end

  def create_practice(clerk_messages, result)
    practice = Practice.new(
      user: @ai_roleplay_session.user,
      practice_theme: @ai_roleplay_session.practice_theme,
      ai_roleplay_session: @ai_roleplay_session,
      duration: result.duration,
      transcription: clerk_messages.join("\n")
    )

    practice.audio.attach(
      io: result.file,
      filename: AUDIO_FILENAME,
      content_type: "audio/webm"
    )

    practice.save!
    practice
  end

  # 失敗時に分析途中のPractice・Analysis・音声を残さない
  def discard(practice)
    return unless practice&.persisted?

    practice.audio.purge if practice.audio.attached?
    practice.destroy!
  rescue StandardError => e
    Rails.logger.error(
      "[AiRoleplayVoiceAnalysisService] 分析途中のPracticeを削除できませんでした: #{e.class}"
    )
  end

  def skip(reason)
    Rails.logger.info(
      "[AiRoleplayVoiceAnalysisService] 音声分析をスキップしました: #{reason}（ai_roleplay_session_id=#{@ai_roleplay_session.id}）"
    )

    nil
  end
end
