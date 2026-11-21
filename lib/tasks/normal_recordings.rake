require "json"

# 廃止した通常録画（Issue #66）の過去データを整理するタスク
#
# 既存の14日間の自動削除（practices:delete_expired）とは別のタスクとし、既存の処理は変更しない。
namespace :practices do
  desc "自動削除が完了した通常録画のPractice・Analysisを整理する（既定はdry-run。削除にはCONFIRMとEXPECTED_COUNTが必要）"
  task cleanup_normal_recordings: :environment do
    confirm = ENV["CONFIRM"].presence
    expected_count = ENV["EXPECTED_COUNT"].presence
    output_path = ENV["OUTPUT"].presence
    service = NormalRecordingCleanupService.new

    # 片方だけ指定された場合は、指定の誤りとして削除せずに終了する
    if confirm.nil? ^ expected_count.nil?
      abort "CONFIRMとEXPECTED_COUNTは両方指定してください（削除は行っていません）"
    end

    # 削除の後で記録の保存に失敗しないよう、保存先は実行前に確認する
    if output_path && File.exist?(output_path)
      abort "OUTPUTのファイルが既に存在します（削除は行っていません）: #{output_path}"
    end

    result =
      begin
        if confirm
          service.execute!(confirm: confirm, expected_count: expected_count)
        else
          service.dry_run
        end
      rescue NormalRecordingCleanupService::SafetyCheckError => e
        abort "#{e.message}（削除は行っていません）"
      end

    json = JSON.pretty_generate(result.as_json)
    puts json

    if output_path
      # 既存の記録を上書きしないよう、新しいファイルとして作成する
      File.open(output_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(json) }
      puts "実行結果を#{output_path}に保存しました。"
    end

    abort "削除の失敗、または削除前後の照合の不一致があります。" unless result.success?
  end
end

namespace :storage do
  desc "Active Storageの保存先とDBのblobを突き合わせ、孤立ファイルの件数を表示する（読み取り専用。ファイルのキーは表示しない）"
  task orphan_check: :environment do
    result = StorageOrphanCheckService.new.call

    puts JSON.pretty_generate(result.as_json)
  rescue StorageOrphanCheckService::UnsupportedServiceError => e
    abort e.message
  rescue StandardError => e
    # 認証情報やバケットの情報を出さないよう、例外のクラス名だけを表示する
    abort "保存先にアクセスできませんでした（#{e.class}）"
  end
end
