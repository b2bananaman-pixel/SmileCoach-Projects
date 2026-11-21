# Active Storageの保存先（本番はGCS）とDBのblobを突き合わせ、孤立ファイルの件数を確認する（読み取り専用）
#
# - orphan_files：保存先にあるが、どのblobにも対応しないファイル（例：DBの記録の削除後にファイルの削除に失敗したもの）
# - missing_files：blobはあるが、保存先にファイルがないもの
#
# ファイルのキーは推測されると録音・録画を取得できるため、結果には件数とblobのIDだけを含め、キーは出力しない。
# ファイルの削除・変更は行わない。
class StorageOrphanCheckService
  class UnsupportedServiceError < StandardError; end

  Result = Struct.new(:service_name, :storage_files, :db_blobs, :orphan_files, :orphan_bytes, :missing_blob_ids, keyword_init: true) do
    def as_json(*)
      {
        service_name: service_name,
        storage_files: storage_files,
        db_blobs: db_blobs,
        orphan_files: orphan_files,
        orphan_bytes: orphan_bytes,
        missing_files: missing_blob_ids.size,
        missing_blob_ids: missing_blob_ids
      }
    end
  end

  def initialize(service: ActiveStorage::Blob.service)
    @service = service
  end

  def call
    storage_sizes = list_storage_files
    blobs = ActiveStorage::Blob.where(service_name: @service.name).pluck(:id, :key)
    blob_keys = blobs.map(&:last).to_set

    orphan_keys = storage_sizes.keys.reject { |key| blob_keys.include?(key) }

    Result.new(
      service_name: @service.name,
      storage_files: storage_sizes.size,
      db_blobs: blobs.size,
      orphan_files: orphan_keys.size,
      orphan_bytes: orphan_keys.sum { |key| storage_sizes[key].to_i },
      missing_blob_ids: blobs.reject { |_id, key| storage_sizes.key?(key) }.map(&:first).sort
    )
  end

  private

  # 保存先のファイルの一覧を { キー => バイト数 } で返す
  def list_storage_files
    case @service.class.name
    when "ActiveStorage::Service::GCSService"
      # GCSServiceはバケットを公開していないため、内部のバケットを読み取り専用で参照する
      @service.send(:bucket).files.all.each_with_object({}) { |file, sizes| sizes[file.name] = file.size }
    when "ActiveStorage::Service::DiskService"
      # DiskServiceは root/キーの先頭2文字/次の2文字/キー の構成で保存する
      Dir.glob(File.join(@service.root, "*", "*", "*")).each_with_object({}) do |path, sizes|
        sizes[File.basename(path)] = File.size(path) if File.file?(path)
      end
    else
      raise UnsupportedServiceError, "#{@service.class.name}には対応していません"
    end
  end
end
