require "test_helper"

# 本番の保存先をus-west1の新バケットへ切り替えても、切り替え前のファイルを旧バケットから読み取り・削除できることを確認する
# 設定ファイルを読むだけで、GCSへの接続や認証情報の読み込みは行わない
class StorageConfigurationTest < ActiveSupport::TestCase
  PRODUCTION_CONFIG_PATH = Rails.root.join("config/environments/production.rb")

  setup do
    # config_for(:storage) は storage.yml の test キーを環境名として扱うため、ファイル全体を直接読む
    @configs = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/storage.yml"))
  end

  test "既存ファイル用のgoogleサービスは旧バケットの設定のまま残す" do
    assert_equal(
      {
        "service" => "GCS",
        "project" => "smilecoach-509411",
        "bucket" => "smilecoach-production-storage"
      },
      @configs["google"]
    )
  end

  test "新しい保存先のgoogle_us_west1サービスはus-west1のバケットを使う" do
    assert_equal(
      {
        "service" => "GCS",
        "project" => "smilecoach-509411",
        "bucket" => "smilecoach-video-us-west1"
      },
      @configs["google_us_west1"]
    )
  end

  test "新旧のサービスは別のバケットを使う" do
    assert_not_equal @configs["google"]["bucket"], @configs["google_us_west1"]["bucket"]
  end

  test "テスト環境と開発環境の保存先はローカルディスクのまま" do
    assert_equal "Disk", @configs["test"]["service"]
    assert_equal "Disk", @configs["local"]["service"]
    assert_equal :test, Rails.application.config.active_storage.service
  end

  test "本番環境は新しいgoogle_us_west1サービスに保存する" do
    assert_equal :google_us_west1, production_active_storage_service
  end

  test "本番環境で使うサービスがstorage.ymlに定義されている" do
    # 定義されていないサービス名を指定すると本番でアプリを起動できないため、設定の整合性を確認する
    assert_includes @configs.keys, production_active_storage_service.to_s
  end

  test "新旧のGCSサービスはどちらも接続せずに構築できる" do
    configurator = ActiveStorage::Service::Configurator.new(@configs)

    [ :google, :google_us_west1 ].each do |name|
      service = configurator.build(name)

      assert_instance_of ActiveStorage::Service::GCSService, service
      assert_equal name, service.name
    end
  end

  private

  def production_active_storage_service
    source = File.read(PRODUCTION_CONFIG_PATH)
    service_names = source.scan(/^\s*config\.active_storage\.service\s*=\s*:(\w+)/).flatten

    assert_equal 1, service_names.size, "production.rbでActive Storageのサービスを1つだけ指定する"

    service_names.first.to_sym
  end
end
