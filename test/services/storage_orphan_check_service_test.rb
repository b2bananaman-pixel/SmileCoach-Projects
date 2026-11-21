require "test_helper"
require "tmpdir"

class StorageOrphanCheckServiceTest < ActiveSupport::TestCase
  SERVICE_NAME = "storage_orphan_check_test".freeze

  setup do
    @root = Dir.mktmpdir
    @service = ActiveStorage::Service::DiskService.new(root: @root)
    @service.name = SERVICE_NAME
  end

  teardown do
    FileUtils.remove_entry(@root)
  end

  test "保存先とDBのblobを突き合わせ、孤立ファイルとファイルのないblobを件数で返す" do
    stored = create_blob_record("stored")
    missing = create_blob_record("missing")
    @service.upload(stored.key, StringIO.new("stored file"))
    @service.upload("orphankey000000000000001", StringIO.new("orphan file!"))

    result = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = StorageOrphanCheckService.new(service: @service).call
    end

    assert_equal SERVICE_NAME, result.service_name
    assert_equal 2, result.storage_files
    assert_equal 2, result.db_blobs
    assert_equal 1, result.orphan_files
    assert_equal "orphan file!".bytesize, result.orphan_bytes
    assert_equal [ missing.id ], result.missing_blob_ids

    # ファイルは削除・変更しない
    assert @service.exist?(stored.key)
    assert @service.exist?("orphankey000000000000001")
  end

  test "結果にファイルのキーを含めない" do
    stored = create_blob_record("stored")
    @service.upload(stored.key, StringIO.new("stored file"))
    @service.upload("orphankey000000000000002", StringIO.new("orphan"))

    json = StorageOrphanCheckService.new(service: @service).call.as_json.to_json

    assert_not_includes json, stored.key
    assert_not_includes json, "orphankey000000000000002"
    assert_equal 1, JSON.parse(json)["orphan_files"]
  end

  test "対応していない保存先の場合は例外を送出する" do
    unsupported = Struct.new(:name).new("unsupported")

    assert_raises(StorageOrphanCheckService::UnsupportedServiceError) do
      StorageOrphanCheckService.new(service: unsupported).call
    end
  end

  private

  # テスト用の保存先はstorage.ymlにないため、検証を省略してblobの記録だけを作成する
  def create_blob_record(label)
    blob = ActiveStorage::Blob.new(
      key: ActiveStorage::Blob.generate_unique_secure_token(length: ActiveStorage::Blob::MINIMUM_TOKEN_LENGTH),
      filename: "#{label}.webm",
      content_type: "audio/webm",
      byte_size: 1,
      checksum: "dummy",
      service_name: SERVICE_NAME
    )
    blob.save!(validate: false)
    blob
  end
end
