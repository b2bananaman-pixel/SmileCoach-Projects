require "test_helper"
require "rake"
require "tmpdir"

class NormalRecordingsTaskTest < ActiveSupport::TestCase
  TASK = "practices:cleanup_normal_recordings".freeze
  ENV_KEYS = %w[CONFIRM EXPECTED_COUNT OUTPUT].freeze

  setup do
    # タスクを重複して読み込むと処理が複数回実行されるため、未定義の場合だけ読み込む
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK)
    Rake::Task[TASK].reenable
    Rake::Task["storage:orphan_check"].reenable

    @original_env = ENV.to_h.slice(*ENV_KEYS)
    ENV_KEYS.each { |key| ENV.delete(key) }

    # fixtureの通常録画（practices(:one)・(:two)）は添付・文字起こしがないため削除できる
    @deletable_ids = [ practices(:one).id, practices(:two).id ].sort
  end

  teardown do
    ENV_KEYS.each { |key| ENV.delete(key) }
    @original_env.each { |key, value| ENV[key] = value }
  end

  test "指定がない場合はdry-runとして結果をJSONで表示し、何も削除しない" do
    output = nil

    assert_no_difference([ "Practice.count", "Analysis.count" ]) do
      output, = capture_io { Rake::Task[TASK].invoke }
    end

    result = JSON.parse(output)
    assert_equal "dry_run", result["mode"]
    assert_equal true, result["success"]
    assert_equal @deletable_ids, result["deletable_practice_ids"]
  end

  test "CONFIRMとEXPECTED_COUNTの片方だけを指定した場合は削除せずに終了する" do
    [ { "CONFIRM" => NormalRecordingCleanupService::CONFIRMATION }, { "EXPECTED_COUNT" => "2" } ].each do |env|
      Rake::Task[TASK].reenable
      ENV_KEYS.each { |key| ENV.delete(key) }
      env.each { |key, value| ENV[key] = value }

      assert_no_difference([ "Practice.count", "Analysis.count" ]) do
        error = assert_raises(SystemExit) { capture_io { Rake::Task[TASK].invoke } }
        assert_not error.success?
      end
    end
  end

  test "CONFIRMまたはEXPECTED_COUNTが一致しない場合は削除せずに終了する" do
    [ [ "yes", "2" ], [ NormalRecordingCleanupService::CONFIRMATION, "3" ], [ NormalRecordingCleanupService::CONFIRMATION, "two" ] ].each do |confirm, expected_count|
      Rake::Task[TASK].reenable
      ENV["CONFIRM"] = confirm
      ENV["EXPECTED_COUNT"] = expected_count

      assert_no_difference([ "Practice.count", "Analysis.count" ]) do
        error = assert_raises(SystemExit) { capture_io { Rake::Task[TASK].invoke } }
        assert_not error.success?
      end
    end
  end

  test "CONFIRMとEXPECTED_COUNTが一致した場合だけ削除し、結果をJSONファイルに保存する" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cleanup_result.json")
      ENV["CONFIRM"] = NormalRecordingCleanupService::CONFIRMATION
      ENV["EXPECTED_COUNT"] = @deletable_ids.size.to_s
      ENV["OUTPUT"] = path

      assert_difference("Practice.count", -@deletable_ids.size) do
        capture_io { Rake::Task[TASK].invoke }
      end

      result = JSON.parse(File.read(path))
      assert_equal "execute", result["mode"]
      assert_equal true, result["success"]
      assert_equal @deletable_ids, result["deleted_practice_ids"]
      assert_empty result["verification_errors"]
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  test "OUTPUTのファイルが既に存在する場合は、削除せずに終了し既存のファイルを上書きしない" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cleanup_result.json")
      File.write(path, "existing")
      ENV["CONFIRM"] = NormalRecordingCleanupService::CONFIRMATION
      ENV["EXPECTED_COUNT"] = @deletable_ids.size.to_s
      ENV["OUTPUT"] = path

      assert_no_difference([ "Practice.count", "Analysis.count" ]) do
        assert_raises(SystemExit) { capture_io { Rake::Task[TASK].invoke } }
      end

      assert_equal "existing", File.read(path)
    end
  end

  test "storage:orphan_checkは件数をJSONで表示し、ファイルのキーを表示しない" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("orphan check"),
      filename: "orphan_check.webm",
      content_type: "audio/webm"
    )

    output, = capture_io { Rake::Task["storage:orphan_check"].invoke }

    result = JSON.parse(output)
    assert_equal "test", result["service_name"]
    assert_operator result["db_blobs"], :>=, 1
    %w[storage_files orphan_files orphan_bytes missing_files missing_blob_ids].each do |key|
      assert result.key?(key), "#{key}を含むこと"
    end
    assert_not_includes output, blob.key
  end
end
