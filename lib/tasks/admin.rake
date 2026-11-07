# 管理者権限の付与・解除は、画面からは行わず、このサーバー側のコマンドからのみ実行する
#
# 実行例:
#   EMAIL=user@example.com bin/rails admin:grant                  # 管理者（admin）にする
#   EMAIL=user@example.com ROLE=super_admin bin/rails admin:grant # 最高管理者（super_admin）にする
#   EMAIL=user@example.com bin/rails admin:revoke                 # 一般ユーザー（user）に戻す
#
# 既存ユーザーだけを対象とし、ユーザーを新規作成しない。
# 最高管理者が0人の場合も、既存ユーザーを最初の最高管理者にできる。最後の最高管理者は降格・解除できない。
# 旧adminカラムも同じトランザクションで同期する（User#change_role!）。
# 個人情報を残さないよう、結果にはメールアドレスではなくユーザーIDを表示する。
namespace :admin do
  grantable_roles = %w[admin super_admin].freeze

  find_target_user = lambda do
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "EMAILを指定してください（例: EMAIL=user@example.com bin/rails admin:grant）" if email.empty?

    User.find_by(email: email) || abort("指定したメールアドレスのユーザーが見つかりません。権限は変更していません。")
  end

  change_role = lambda do |user, role|
    user.change_role!(role)

    puts "ユーザーID #{user.id} の権限を#{role}に変更しました（role: #{user.reload.role}）"
  rescue ActiveRecord::RecordNotSaved
    abort "#{User::LAST_SUPER_ADMIN_ERROR_MESSAGE}。権限は変更していません。"
  end

  desc "既存ユーザーに管理者権限を付与する（EMAILで指定。ROLE=super_adminで最高管理者、省略時はadmin）"
  task grant: :environment do
    role = ENV.fetch("ROLE", "admin").to_s.strip
    abort "ROLEには#{grantable_roles.join('または')}を指定してください。権限は変更していません。" unless grantable_roles.include?(role)

    change_role.call(find_target_user.call, role)
  end

  desc "既存ユーザーの管理者権限を解除し、一般ユーザーに戻す（EMAILで指定）"
  task revoke: :environment do
    change_role.call(find_target_user.call, "user")
  end
end
