require "digest"

# 廃止した通常録画（Issue #66）の過去データのうち、Practice・AnalysisのDBの記録だけを整理する
#
# - 録音・録画・文字起こしは既存の14日間の自動削除（PracticeRetentionService）に任せ、このServiceではファイルを削除しない
# - 削除候補は ai_roleplay_session_id IS NULL AND practice_theme_id IS NOT NULL の通常録画だけとする
# - 添付（audio・video・その他すべて）や文字起こしが残っているPracticeは「保留」として削除しない
# - ai_roleplay_session_id・practice_theme_id の両方がNULLのPracticeは「異常値」として削除しない
# - AIロープレのデータ（セッション・会話・評価・Practice・Analysis・録音・録画）は一切変更しない
#
# 削除は1件ごとのトランザクションで行い、削除直前に行をロックして条件を再確認する。
# 途中で失敗しても、削除済みの記録は確定し、残りは次回の実行で処理できる。
class NormalRecordingCleanupService
  CONFIRMATION = "DELETE_NORMAL_RECORDINGS".freeze

  class SafetyCheckError < StandardError; end

  Result = Struct.new(
    :mode,
    :deletable_practice_ids,
    :pending,
    :anomaly_practice_ids,
    :deleted_practice_ids,
    :deleted_analysis_ids,
    :skipped,
    :failed_practice_ids,
    :before,
    :after,
    :verification_errors,
    keyword_init: true
  ) do
    def success?
      failed_practice_ids.empty? && verification_errors.empty?
    end

    def as_json(*)
      {
        mode: mode,
        success: success?,
        deletable_count: deletable_practice_ids.size,
        deletable_practice_ids: deletable_practice_ids,
        pending_count: pending.size,
        pending: pending,
        anomaly_count: anomaly_practice_ids.size,
        anomaly_practice_ids: anomaly_practice_ids,
        deleted_practice_ids: deleted_practice_ids,
        deleted_analysis_ids: deleted_analysis_ids,
        skipped: skipped,
        failed_practice_ids: failed_practice_ids,
        before: before,
        after: after,
        verification_errors: verification_errors
      }
    end
  end

  # 通常録画の削除候補（AIロープレの音声分析用Practiceは含まない）
  def self.candidate_scope
    Practice.where(ai_roleplay_session_id: nil).where.not(practice_theme_id: nil)
  end

  # 練習テーマもAIロープレもないPractice（通常は存在しない。削除せず報告だけする）
  def self.anomaly_scope
    Practice.where(ai_roleplay_session_id: nil, practice_theme_id: nil)
  end

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  # 削除対象・保留・異常値と、現在の件数を返す（DB・ストレージは変更しない）
  def dry_run
    classification = classify
    snapshot_now = snapshot

    Result.new(
      mode: "dry_run",
      **classification,
      deleted_practice_ids: [],
      deleted_analysis_ids: [],
      skipped: [],
      failed_practice_ids: [],
      before: snapshot_now,
      after: nil,
      verification_errors: []
    )
  end

  # confirm と expected_count が一致した場合だけ、削除できる通常録画のPractice・Analysisを削除する
  #
  # expected_count には、直前のdry-runで確認した削除できる件数を指定する。
  # 件数が変わっていた場合は、何も削除せずに SafetyCheckError を送出する。
  def execute!(confirm:, expected_count:)
    raise SafetyCheckError, "CONFIRMが一致しません" unless confirm == CONFIRMATION

    expected = parse_expected_count(expected_count)
    classification = classify
    actual = classification[:deletable_practice_ids].size

    if actual != expected
      raise SafetyCheckError, "削除できる件数（#{actual}件）がEXPECTED_COUNT（#{expected}件）と一致しません"
    end

    before = snapshot
    deleted_practice_ids = []
    deleted_analysis_ids = []
    skipped = []
    failed_practice_ids = []

    classification[:deletable_practice_ids].each do |practice_id|
      outcome = delete_practice(practice_id)

      case outcome[:status]
      when :deleted
        deleted_practice_ids << practice_id
        deleted_analysis_ids.concat(outcome[:analysis_ids])
      else
        skipped << { practice_id: practice_id, reason: outcome[:reason] }
      end
    rescue StandardError => e
      failed_practice_ids << practice_id

      # 例外メッセージに個人情報やストレージのキーが含まれる可能性があるため、IDとクラス名のみ記録する
      @logger.error("[NormalRecordingCleanupService] 削除に失敗しました: practice_id=#{practice_id} (#{e.class})")
    end

    after = snapshot

    Result.new(
      mode: "execute",
      **classification,
      deleted_practice_ids: deleted_practice_ids,
      deleted_analysis_ids: deleted_analysis_ids,
      skipped: skipped,
      failed_practice_ids: failed_practice_ids,
      before: before,
      after: after,
      verification_errors: verify(
        before: before,
        after: after,
        deleted_practice_ids: deleted_practice_ids,
        deleted_analysis_ids: deleted_analysis_ids,
        kept_practice_ids: classification[:pending].map { |item| item[:practice_id] } + classification[:anomaly_practice_ids]
      )
    )
  end

  private

  def parse_expected_count(value)
    count = Integer(value.to_s, 10)
    raise SafetyCheckError, "EXPECTED_COUNTは0以上の整数を指定してください" if count.negative?

    count
  rescue ArgumentError
    raise SafetyCheckError, "EXPECTED_COUNTは0以上の整数を指定してください"
  end

  def classify
    candidates = self.class.candidate_scope.order(:id).pluck(:id, :transcription)
    attachment_names = practice_attachment_names(candidates.map(&:first))

    deletable_practice_ids = []
    pending = []

    candidates.each do |practice_id, transcription|
      reasons = (attachment_names[practice_id] || []).sort
      reasons << "transcription" if transcription.present?

      if reasons.empty?
        deletable_practice_ids << practice_id
      else
        pending << { practice_id: practice_id, reasons: reasons }
      end
    end

    {
      deletable_practice_ids: deletable_practice_ids,
      pending: pending,
      anomaly_practice_ids: self.class.anomaly_scope.order(:id).pluck(:id)
    }
  end

  # audio・video に限らず、Practiceに紐づくすべての添付を確認する
  def practice_attachment_names(practice_ids)
    ActiveStorage::Attachment
      .where(record_type: "Practice", record_id: practice_ids)
      .pluck(:record_id, :name)
      .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(record_id, name), names|
        names[record_id] << name unless names[record_id].include?(name)
      end
  end

  # 削除直前に行をロックしてDBから読み直し、条件をすべて満たす場合だけ削除する
  #
  # トランザクションのブロックからreturnで抜けると、Railsのバージョンによって挙動が異なるため、条件分岐で結果を返す。
  def delete_practice(practice_id)
    Practice.transaction do
      practice = Practice.lock.find_by(id: practice_id)
      reason = practice.nil? ? "already_deleted" : ineligible_reason(practice)

      if reason
        { status: :skipped, reason: reason }
      else
        analysis_ids = Analysis.where(practice_id: practice.id).order(:id).pluck(:id)

        Analysis.where(id: analysis_ids).find_each(&:destroy!)
        practice.reload.destroy!

        { status: :deleted, analysis_ids: analysis_ids }
      end
    end
  end

  def ineligible_reason(practice)
    return "ai_roleplay_practice" if practice.ai_roleplay_session_id.present?
    return "anomaly" if practice.practice_theme_id.nil?
    return "transcription" if practice.transcription.present?
    return "attachment" if ActiveStorage::Attachment.exists?(record_type: "Practice", record_id: practice.id)

    nil
  end

  # 削除前後で比較する件数と、関連IDの一覧のハッシュ値
  #
  # preserved は削除の前後で変わってはいけない（AIロープレ・教材・ユーザー・ストレージ）。
  def snapshot
    normal_practice_ids = Practice.where(ai_roleplay_session_id: nil).select(:id)
    ai_practices = Practice.where.not(ai_roleplay_session_id: nil)
    ai_analyses = Analysis.where(practice_id: ai_practices.select(:id))
    ai_practice_attachments = ActiveStorage::Attachment.where(record_type: "Practice", record_id: ai_practices.select(:id))
    session_attachments = ActiveStorage::Attachment.where(record_type: "AiRoleplaySession")

    {
      normal_recordings: {
        candidate_practices: self.class.candidate_scope.count,
        anomaly_practices: self.class.anomaly_scope.count,
        analyses: Analysis.where(practice_id: normal_practice_ids).count,
        attachments: ActiveStorage::Attachment.where(record_type: "Practice", record_id: normal_practice_ids).count,
        with_transcription: Practice.where(ai_roleplay_session_id: nil).where.not(transcription: [ nil, "" ]).count
      },
      preserved: {
        ai_roleplay_sessions: count_and_digest(AiRoleplaySession),
        ai_roleplay_messages: count_and_digest(AiRoleplayMessage),
        ai_roleplay_evaluations: count_and_digest(AiRoleplayEvaluation),
        ai_roleplay_practices: count_and_digest(ai_practices),
        ai_roleplay_analyses: count_and_digest(ai_analyses),
        ai_roleplay_practice_attachments: count_and_digest(ai_practice_attachments),
        ai_roleplay_session_attachments: count_and_digest(session_attachments),
        active_storage_attachments: count_and_digest(ActiveStorage::Attachment),
        active_storage_blobs: count_and_digest(ActiveStorage::Blob),
        practice_themes: count_and_digest(PracticeTheme),
        products: count_and_digest(Product),
        product_categories: count_and_digest(ProductCategory),
        users: count_and_digest(User)
      }
    }
  end

  def count_and_digest(scope)
    ids = scope.order(:id).pluck(:id)

    { count: ids.size, ids_sha256: Digest::SHA256.hexdigest(ids.join(",")) }
  end

  def verify(before:, after:, deleted_practice_ids:, deleted_analysis_ids:, kept_practice_ids:)
    errors = []

    before[:preserved].each do |name, value|
      errors << "#{name}が削除の前後で変わりました" unless after[:preserved][name] == value
    end

    errors << "削除したPracticeが残っています" if Practice.where(id: deleted_practice_ids).exists?
    errors << "削除したAnalysisが残っています" if Analysis.where(id: deleted_analysis_ids).exists?

    if Practice.where(id: kept_practice_ids).count != kept_practice_ids.size
      errors << "保留・異常値のPracticeが削除されています"
    end

    errors
  end
end
