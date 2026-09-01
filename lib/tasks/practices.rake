namespace :practices do
  desc "14日以上経過した練習履歴を削除する"
  task delete_expired: :environment do
    deleted_count = PracticeRetentionService.delete_expired

    puts "#{deleted_count}件の練習履歴を削除しました。"
  end
end
