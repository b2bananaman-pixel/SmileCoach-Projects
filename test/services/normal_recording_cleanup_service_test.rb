require "test_helper"

class NormalRecordingCleanupServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  AUDIO_FILE = Rails.root.join("test/fixtures/files/test_volume.webm")

  setup do
    @user = users(:one)
    @practice_theme = practice_themes(:one)

    # 削除できる通常録画（添付・文字起こしなし）。fixtureの通常録画（practices(:one)・(:two)）も削除できる
    @deletable = Practice.create!(user: @user, practice_theme: @practice_theme)
    @deletable_analysis = Analysis.create!(practice: @deletable, total_score: 80)

    # 保留：録音・録画・文字起こし・その他の添付が残っている通常録画
    @pending_audio = Practice.create!(user: @user, practice_theme: @practice_theme)
    attach(@pending_audio, :audio)
    @pending_video = Practice.create!(user: @user, practice_theme: @practice_theme)
    attach(@pending_video, :video)
    @pending_transcription = Practice.create!(user: @user, practice_theme: @practice_theme, transcription: "いらっしゃいませ")
    @pending_other = Practice.create!(user: @user, practice_theme: @practice_theme)
    ActiveStorage::Attachment.create!(name: "other", record: @pending_other, blob: create_blob)

    # 異常値：練習テーマもAIロープレもないPractice（モデルの検証を通らないため、列を直接更新して作る）
    @anomaly = Practice.create!(user: @user, practice_theme: @practice_theme)
    @anomaly.update_columns(practice_theme_id: nil)

    # AIロープレのデータ（セッション・会話・評価・音声分析用Practice・Analysis・録音・録画）
    @session = AiRoleplaySession.create!(user: @user, practice_theme: @practice_theme)
    @session.ai_roleplay_messages.create!(role: "user", content: "いらっしゃいませ")
    AiRoleplayEvaluation.create!(ai_roleplay_session: @session, hearing_score: 4)
    @session.video.attach(io: File.open(AUDIO_FILE), filename: "ai_roleplay.webm", content_type: "video/webm")
    @ai_practice = Practice.create!(user: @user, practice_theme: @practice_theme, ai_roleplay_session: @session)
    attach(@ai_practice, :audio)
    @ai_analysis = Analysis.create!(practice: @ai_practice, total_score: 77)

    # 添付・文字起こしがないAIロープレのPracticeも、通常録画として扱わない
    @bare_session = AiRoleplaySession.create!(user: @user, practice_theme: @practice_theme)
    @bare_ai_practice = Practice.create!(user: @user, practice_theme: @practice_theme, ai_roleplay_session: @bare_session)
    @bare_ai_analysis = Analysis.create!(practice: @bare_ai_practice, total_score: 70)

    @expected_deletable_ids = [ practices(:one).id, practices(:two).id, @deletable.id ].sort
  end

  test "dry-runは削除できる・保留・異常値を分類し、DBとストレージを変更しない" do
    result = nil

    assert_counts_unchanged do
      assert_no_enqueued_jobs do
        result = NormalRecordingCleanupService.new.dry_run
      end
    end

    assert_equal "dry_run", result.mode
    assert_equal @expected_deletable_ids, result.deletable_practice_ids
    assert_equal(
      [
        { practice_id: @pending_audio.id, reasons: [ "audio" ] },
        { practice_id: @pending_video.id, reasons: [ "video" ] },
        { practice_id: @pending_transcription.id, reasons: [ "transcription" ] },
        { practice_id: @pending_other.id, reasons: [ "other" ] }
      ],
      result.pending
    )
    assert_equal [ @anomaly.id ], result.anomaly_practice_ids
    assert_empty result.deleted_practice_ids
    assert result.success?
    assert_all_files_exist
  end

  test "削除できる通常録画だけをAnalysisとともに削除し、AIロープレ・保留・異常値・教材・ユーザーは残す" do
    deletable_analysis_ids = Analysis.where(practice_id: @expected_deletable_ids).order(:id).pluck(:id)
    preserved_before = preserved_records
    result = nil

    assert_no_enqueued_jobs do
      result = NormalRecordingCleanupService.new.execute!(
        confirm: NormalRecordingCleanupService::CONFIRMATION,
        expected_count: @expected_deletable_ids.size
      )
    end

    assert result.success?, result.verification_errors.inspect
    assert_equal "execute", result.mode
    assert_equal @expected_deletable_ids, result.deleted_practice_ids
    assert_equal deletable_analysis_ids, result.deleted_analysis_ids.sort
    assert_not Practice.where(id: @expected_deletable_ids).exists?
    assert_not Analysis.where(id: deletable_analysis_ids).exists?

    # 保留・異常値の通常録画は残る
    [ @pending_audio, @pending_video, @pending_transcription, @pending_other, @anomaly ].each do |practice|
      assert Practice.exists?(practice.id), "practice_id=#{practice.id}は残ること"
    end

    # AIロープレ・教材・ユーザー・ストレージは削除の前後で同じ
    assert_equal preserved_before, preserved_records
    assert @session.reload.video.attached?
    assert @ai_practice.reload.audio.attached?
    assert_equal @ai_analysis, @ai_practice.analysis
    assert_equal @bare_ai_analysis, @bare_ai_practice.reload.analysis
    assert_all_files_exist

    assert_equal result.before[:preserved], result.after[:preserved]
    # 削除後の通常録画の候補は、保留の4件だけになる（異常値は候補に含めない）
    assert_equal 4, result.after[:normal_recordings][:candidate_practices]
    assert_equal 1, result.after[:normal_recordings][:anomaly_practices]
  end

  test "CONFIRMが一致しない場合は何も削除しない" do
    [ nil, "", "delete_normal_recordings", "YES" ].each do |confirm|
      assert_counts_unchanged do
        assert_raises(NormalRecordingCleanupService::SafetyCheckError) do
          NormalRecordingCleanupService.new.execute!(confirm: confirm, expected_count: @expected_deletable_ids.size)
        end
      end
    end
  end

  test "EXPECTED_COUNTが削除できる件数と一致しない場合や不正な場合は何も削除しない" do
    [ @expected_deletable_ids.size + 1, @expected_deletable_ids.size - 1, nil, "", "abc", "-1", "3.0" ].each do |expected_count|
      assert_counts_unchanged do
        assert_raises(NormalRecordingCleanupService::SafetyCheckError, "expected_count=#{expected_count.inspect}") do
          NormalRecordingCleanupService.new.execute!(
            confirm: NormalRecordingCleanupService::CONFIRMATION,
            expected_count: expected_count
          )
        end
      end
    end
  end

  test "削除の直前にDBから読み直し、条件を満たさなくなったPracticeは削除しない" do
    service = NormalRecordingCleanupService.new
    missing_id = Practice.maximum(:id) + 1_000

    # 分類の後に状態が変わった場合を再現するため、条件を満たさないIDを削除対象として渡す
    classification = {
      deletable_practice_ids: [ @deletable.id, @ai_practice.id, @bare_ai_practice.id, @anomaly.id, @pending_audio.id, @pending_transcription.id, missing_id ],
      pending: [],
      anomaly_practice_ids: []
    }

    result = nil

    service.stub(:classify, classification) do
      result = service.execute!(confirm: NormalRecordingCleanupService::CONFIRMATION, expected_count: 7)
    end

    assert_equal [ @deletable.id ], result.deleted_practice_ids
    assert_equal(
      [
        { practice_id: @ai_practice.id, reason: "ai_roleplay_practice" },
        { practice_id: @bare_ai_practice.id, reason: "ai_roleplay_practice" },
        { practice_id: @anomaly.id, reason: "anomaly" },
        { practice_id: @pending_audio.id, reason: "attachment" },
        { practice_id: @pending_transcription.id, reason: "transcription" },
        { practice_id: missing_id, reason: "already_deleted" }
      ],
      result.skipped
    )
    assert Practice.exists?(@ai_practice.id)
    assert Practice.exists?(@bare_ai_practice.id)
    assert Practice.exists?(@anomaly.id)
    assert Practice.exists?(@pending_audio.id)
    assert Analysis.exists?(@ai_analysis.id)
  end

  test "途中で失敗しても他の削除は確定し、再実行で残りを削除できる" do
    service = NormalRecordingCleanupService.new
    original_delete = service.method(:delete_practice)
    failing_id = @deletable.id
    logs = StringIO.new
    service.instance_variable_set(:@logger, Logger.new(logs))

    first = nil

    service.stub(:delete_practice, ->(practice_id) {
      raise "テスト用の失敗 key=secret-storage-key" if practice_id == failing_id

      original_delete.call(practice_id)
    }) do
      first = service.execute!(confirm: NormalRecordingCleanupService::CONFIRMATION, expected_count: 3)
    end

    assert_not first.success?
    assert_equal [ failing_id ], first.failed_practice_ids
    assert_equal [ practices(:one).id, practices(:two).id ].sort, first.deleted_practice_ids
    assert Practice.exists?(failing_id)
    assert Analysis.exists?(@deletable_analysis.id)

    # ログにはIDとクラス名だけを出し、例外メッセージ（キーなど）は出さない
    assert_includes logs.string, "practice_id=#{failing_id} (RuntimeError)"
    assert_not_includes logs.string, "secret-storage-key"

    retry_dry_run = NormalRecordingCleanupService.new.dry_run
    assert_equal [ failing_id ], retry_dry_run.deletable_practice_ids

    second = NormalRecordingCleanupService.new.execute!(confirm: NormalRecordingCleanupService::CONFIRMATION, expected_count: 1)

    assert second.success?
    assert_equal [ failing_id ], second.deleted_practice_ids
    assert_not Analysis.exists?(@deletable_analysis.id)
  end

  test "2回目の実行では削除するものがなく、何も変更しない" do
    NormalRecordingCleanupService.new.execute!(confirm: NormalRecordingCleanupService::CONFIRMATION, expected_count: 3)

    result = nil

    assert_counts_unchanged do
      result = NormalRecordingCleanupService.new.execute!(confirm: NormalRecordingCleanupService::CONFIRMATION, expected_count: 0)
    end

    assert result.success?
    assert_empty result.deleted_practice_ids
  end

  test "自動削除で添付と文字起こしがなくなった通常録画は、次の実行で削除できるようになる" do
    PracticeRetentionService.stub(:retention_period, 0.seconds) do
      PracticeRetentionService.delete_expired
    end

    assert_includes NormalRecordingCleanupService.new.dry_run.deletable_practice_ids, @pending_transcription.id
    # 録音・録画は自動削除の対象だが、その他の添付は残るため保留のまま
    assert_equal [ @pending_other.id ], NormalRecordingCleanupService.new.dry_run.pending.map { |item| item[:practice_id] }
    # AIロープレの音声も既存の自動削除の対象（既存の動作を変えていないこと）
    assert_not @ai_practice.reload.audio.attached?
  end

  test "結果はJSONに変換でき、ストレージのキーを含まない" do
    json = NormalRecordingCleanupService.new.dry_run.as_json.to_json

    parsed = JSON.parse(json)
    assert_equal "dry_run", parsed["mode"]
    assert_equal @expected_deletable_ids.size, parsed["deletable_count"]
    assert_equal 4, parsed["pending_count"]
    assert_equal 1, parsed["anomaly_count"]

    ActiveStorage::Blob.pluck(:key).each do |key|
      assert_not_includes json, key
    end
  end

  private

  def attach(record, name)
    record.public_send(name).attach(io: File.open(AUDIO_FILE), filename: "#{name}.webm", content_type: "audio/webm")
  end

  def create_blob
    ActiveStorage::Blob.create_and_upload!(io: File.open(AUDIO_FILE), filename: "other.webm", content_type: "audio/webm")
  end

  # 各テーブルの件数を、ブロックの実行前後で比較する
  def assert_counts_unchanged
    before = counts
    yield
    assert_equal before, counts
  end

  def counts
    [
      Practice.count, Analysis.count, AiRoleplaySession.count, AiRoleplayMessage.count, AiRoleplayEvaluation.count,
      ActiveStorage::Attachment.count, ActiveStorage::Blob.count, PracticeTheme.count, Product.count,
      ProductCategory.count, User.count
    ]
  end

  def preserved_records
    {
      sessions: AiRoleplaySession.order(:id).pluck(:id),
      messages: AiRoleplayMessage.order(:id).pluck(:id),
      evaluations: AiRoleplayEvaluation.order(:id).pluck(:id),
      ai_practices: Practice.where.not(ai_roleplay_session_id: nil).order(:id).pluck(:id),
      ai_analyses: Analysis.where(practice_id: Practice.where.not(ai_roleplay_session_id: nil).select(:id)).order(:id).pluck(:id),
      attachments: ActiveStorage::Attachment.order(:id).pluck(:id),
      blobs: ActiveStorage::Blob.order(:id).pluck(:id),
      practice_themes: PracticeTheme.order(:id).pluck(:id),
      products: Product.order(:id).pluck(:id),
      product_categories: ProductCategory.order(:id).pluck(:id),
      users: User.order(:id).pluck(:id)
    }
  end

  def assert_all_files_exist
    ActiveStorage::Blob.find_each do |blob|
      assert blob.service.exist?(blob.key), "blob_id=#{blob.id}のファイルが残っていること"
    end
  end
end
