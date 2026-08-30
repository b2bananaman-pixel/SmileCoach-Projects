namespace :practices do
  desc "14日以上経過した練習履歴を削除する"
  task delete_expired: :environment do
    cutoff_time = 14.days.ago

    expired_practices = Practice.where("created_at < ?", cutoff_time)

    deleted_count = expired_practices.count

    expired_practices.find_each(&:destroy)

    puts "#{deleted_count}件の練習履歴を削除しました。"
  end
end
