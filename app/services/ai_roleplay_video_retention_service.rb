# 保持期間を過ぎたAIロープレの録画だけを削除する
#
# セッション・評価・会話・Practiceのレコードは残し、評価画面は「録画データはありません」と表示する。
# 保持期間は通常練習と同じ PRACTICE_RETENTION_DAYS（デフォルト14日）を使う。
# 削除は AI_ROLEPLAY_VIDEO_RETENTION_ENABLED が "true" の場合だけ実行し、dry-runは常に実行できる。
class AiRoleplayVideoRetentionService
  ENABLED_ENV_KEY = "AI_ROLEPLAY_VIDEO_RETENTION_ENABLED".freeze

  Result = Struct.new(:deleted_count, :failed_count, keyword_init: true)

  # 誤って有効にしないよう、"true" 以外（未設定・空文字・不正値）はすべて無効とする
  def self.enabled?
    ENV[ENABLED_ENV_KEY] == "true"
  end

  def self.delete_expired
    new.delete_expired
  end

  # 削除対象のセッションIDを返す（DB・ストレージは変更しない）
  def self.expired_session_ids
    new.expired_session_ids
  end

  def delete_expired
    deleted_count = 0
    failed_count = 0

    expired_sessions.includes(video_attachment: :blob).find_each do |ai_roleplay_session|
      purge_video(ai_roleplay_session)
      deleted_count += 1
    rescue StandardError => e
      failed_count += 1

      # 例外メッセージにストレージのキーやURLが含まれる可能性があるため、IDとクラス名のみ記録する
      Rails.logger.error(
        "[AiRoleplayVideoRetentionService] 録画を削除できませんでした: ai_roleplay_session_id=#{ai_roleplay_session.id} (#{e.class})"
      )
    end

    Result.new(deleted_count: deleted_count, failed_count: failed_count)
  end

  def expired_session_ids
    expired_sessions.order(:id).pluck(:id)
  end

  private

  # 録画が添付されているセッションだけを対象にする
  def expired_sessions
    AiRoleplaySession
      .joins(:video_attachment)
      .where(ai_roleplay_sessions: { created_at: ...PracticeRetentionService.retention_period.ago })
  end

  # 先にストレージのファイルを削除し、失敗した場合は添付情報をDBに残して次回の実行で再試行できるようにする
  # （purgeはDBのレコードを削除してからファイルを削除するため、ファイル削除に失敗すると追跡できなくなる）
  # purge内のファイル削除は、削除済みのファイルを無視するため2回目でも失敗しない
  def purge_video(ai_roleplay_session)
    attachment = ai_roleplay_session.video_attachment

    # 他のレコードと共有しているblobはファイルを残し、このセッションとの関連付けだけを外す
    if shared_blob?(attachment)
      ai_roleplay_session.video.detach
      return
    end

    attachment.blob.delete
    purge_video_record(ai_roleplay_session)
  end

  def shared_blob?(attachment)
    ActiveStorage::Attachment.where(blob_id: attachment.blob_id).where.not(id: attachment.id).exists?
  end

  # ファイル削除後にDBの添付情報とblobを削除する
  def purge_video_record(ai_roleplay_session)
    ai_roleplay_session.video.purge
  end
end
