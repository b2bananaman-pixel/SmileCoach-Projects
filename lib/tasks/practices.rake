namespace :practices do
  desc "14日を過ぎた練習の録音・動画・文字起こしとAIロープレの録画を削除する"
  task delete_expired: :environment do
    processed_count = PracticeRetentionService.delete_expired

    puts "#{processed_count}件の期限切れデータを削除しました。"

    if AiRoleplayVideoRetentionService.enabled?
      video_result = AiRoleplayVideoRetentionService.delete_expired

      puts "AIロープレの録画を#{video_result.deleted_count}件削除しました（失敗: #{video_result.failed_count}件）。"

      # 失敗を検知できるよう、1件でも失敗した場合は終了コードを非0にする
      abort "AIロープレの録画の削除に#{video_result.failed_count}件失敗しました。" if video_result.failed_count.positive?
    else
      puts "AIロープレの録画削除は無効のためスキップしました（#{AiRoleplayVideoRetentionService::ENABLED_ENV_KEY}が未設定または\"true\"以外）。"
    end
  end

  desc "14日を過ぎたAIロープレの録画の削除対象を表示する（データは変更しない・有効/無効に関係なく実行できる）"
  task delete_expired_dry_run: :environment do
    session_ids = AiRoleplayVideoRetentionService.expired_session_ids

    puts "[dry-run] 削除対象のAIロープレ録画: #{session_ids.size}件"
    puts "[dry-run] ai_roleplay_session_id: #{session_ids.join(', ')}" if session_ids.any?
  end
end
