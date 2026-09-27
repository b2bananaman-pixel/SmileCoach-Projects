namespace :practices do
  desc "14日を過ぎた練習の録音・動画・文字起こしを削除する"
  task delete_expired: :environment do
    processed_count = PracticeRetentionService.delete_expired

    puts "#{processed_count}件の期限切れデータを削除しました。"
  end
end
