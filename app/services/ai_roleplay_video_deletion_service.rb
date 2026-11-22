# ユーザーが選んだAIロープレの録画だけを削除する（Issue #89）
#
# セッション・評価・会話・Practice（発話音声・文字起こし）・Analysisは削除しない。
# AiRoleplaySessionをdestroyすると、dependent: :destroyで学習記録まで削除されるため、録画の添付だけを削除する。
#
# 14日間の自動削除（AiRoleplayVideoRetentionService）と同じく、ストレージのファイルを先に削除し、
# その後にDBの添付情報とblobを削除する（ファイルの削除に失敗した場合は添付情報を残し、再度削除できるようにする）。
# 本番のジョブはプロセス内で実行されるため（async）、再起動で失われないよう purge_later は使わず同期的に削除する。
class AiRoleplayVideoDeletionService
  Result = Struct.new(:status, keyword_init: true) do
    def deleted?
      status == :deleted
    end

    def already_deleted?
      status == :already_deleted
    end
  end

  def initialize(ai_roleplay_session:)
    @ai_roleplay_session = ai_roleplay_session
  end

  # 削除した場合は :deleted、録画がない（削除済みを含む）場合は :already_deleted を返す
  # ストレージやDBの削除に失敗した場合は例外を送出する（トランザクションにより添付情報は残る）
  def call
    deleted = ActiveStorage::Attachment.transaction do
      # 自動削除と同時に動いても安全なよう、添付情報の行をロックしてから最新の状態を確認する
      #
      # 自動削除はAttachment#purgeで「添付情報の行 → セッションの行（touch）」の順に更新するため、
      # セッションの行を先にロックすると、ロックの順番が逆になりデッドロックになる可能性がある。
      # 同じ順番になるよう、添付情報の行だけをロックする。
      attachment = locked_video_attachment

      purge(attachment) if attachment
      attachment.present?
    end

    # 呼び出し元のセッションに読み込み済みの添付情報を残さない
    @ai_roleplay_session.reload

    Result.new(status: deleted ? :deleted : :already_deleted)
  end

  private

  def locked_video_attachment
    ActiveStorage::Attachment
      .lock
      .includes(:blob)
      .find_by(record_type: AiRoleplaySession.name, record_id: @ai_roleplay_session.id, name: "video")
  end

  def purge(attachment)
    # 他のレコードと共有しているblobはファイルを残し、このセッションとの関連付けだけを外す
    if shared_blob?(attachment)
      attachment.delete
      return
    end

    # ファイルを先に削除する（削除済みのファイルは無視されるため、自動削除と重なっても失敗しない）
    attachment.blob.delete

    # 添付情報を削除し、セッションをtouchした後にblobのレコードを削除する
    attachment.purge
  end

  def shared_blob?(attachment)
    ActiveStorage::Attachment.where(blob_id: attachment.blob_id).where.not(id: attachment.id).exists?
  end
end
