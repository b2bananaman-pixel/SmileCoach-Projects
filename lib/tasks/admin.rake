# 管理者権限の付与・解除は、画面からは行わず、このサーバー側のコマンドからのみ実行する
#
# 実行例:
#   EMAIL=user@example.com bin/rails admin:grant
#   EMAIL=user@example.com bin/rails admin:revoke
#
# 既存ユーザーだけを対象とし、ユーザーを新規作成しない。
# 個人情報を残さないよう、結果にはメールアドレスではなくユーザーIDを表示する。
namespace :admin do
  find_target_user = lambda do
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "EMAILを指定してください（例: EMAIL=user@example.com bin/rails admin:grant）" if email.empty?

    User.find_by(email: email) || abort("指定したメールアドレスのユーザーが見つかりません。管理者権限は変更していません。")
  end

  desc "既存ユーザーに管理者権限を付与する（EMAILで指定）"
  task grant: :environment do
    user = find_target_user.call
    user.update!(admin: true)

    puts "ユーザーID #{user.id} に管理者権限を付与しました（admin: #{user.reload.admin?}）"
  end

  desc "既存ユーザーの管理者権限を解除する（EMAILで指定）"
  task revoke: :environment do
    user = find_target_user.call
    user.update!(admin: false)

    puts "ユーザーID #{user.id} の管理者権限を解除しました（admin: #{user.reload.admin?}）"
  end
end
