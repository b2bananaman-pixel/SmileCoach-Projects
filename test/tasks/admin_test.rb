require "test_helper"
require "rake"

class AdminTaskTest < ActiveSupport::TestCase
  setup do
    # タスクを重複して読み込むと処理が複数回実行されるため、未定義の場合だけ読み込む
    Rails.application.load_tasks unless Rake::Task.task_defined?("admin:grant")
    Rake::Task["admin:grant"].reenable
    Rake::Task["admin:revoke"].reenable

    @user = users(:one)
    @original_email = ENV["EMAIL"]
    @original_role = ENV["ROLE"]
    ENV["ROLE"] = nil
  end

  teardown do
    ENV["EMAIL"] = @original_email
    ENV["ROLE"] = @original_role
  end

  test "admin:grantで既存ユーザーに管理者権限を付与し、旧adminカラムも同期する" do
    ENV["EMAIL"] = @user.email

    output, = capture_io { Rake::Task["admin:grant"].invoke }

    assert @user.reload.admin?
    assert_equal true, legacy_admin_column(@user)
    assert_includes output, "ユーザーID #{@user.id} の権限をadminに変更しました（role: admin）"
  end

  test "ROLE=super_adminで既存ユーザーを最高管理者にする" do
    ENV["EMAIL"] = @user.email
    ENV["ROLE"] = "super_admin"

    output, = capture_io { Rake::Task["admin:grant"].invoke }

    assert @user.reload.super_admin?
    assert_equal true, legacy_admin_column(@user)
    assert_includes output, "ユーザーID #{@user.id} の権限をsuper_adminに変更しました（role: super_admin）"
  end

  test "最高管理者が0人の場合も最初の最高管理者を設定できる" do
    User.where(role: :super_admin).update_all(role: User.roles[:admin])
    ENV["EMAIL"] = @user.email
    ENV["ROLE"] = "super_admin"

    capture_io { Rake::Task["admin:grant"].invoke }

    assert_equal [ @user.id ], User.super_admin.pluck(:id)
  end

  test "admin:revokeで既存ユーザーの管理者権限を解除し、旧adminカラムも同期する" do
    admin = users(:admin)
    ENV["EMAIL"] = admin.email

    output, = capture_io { Rake::Task["admin:revoke"].invoke }

    assert admin.reload.user?
    assert_equal false, legacy_admin_column(admin)
    assert_includes output, "ユーザーID #{admin.id} の権限をuserに変更しました（role: user）"
  end

  test "最後の最高管理者は解除できない" do
    super_admin = users(:super_admin)
    ENV["EMAIL"] = super_admin.email

    _output, error_output = capture_io do
      assert_raises(SystemExit) { Rake::Task["admin:revoke"].invoke }
    end

    assert super_admin.reload.super_admin?
    assert_equal true, legacy_admin_column(super_admin)
    assert_includes error_output, "最後の最高管理者の権限は変更・削除できません。権限は変更していません。"
  end

  test "最後の最高管理者はROLE=adminで降格できない" do
    super_admin = users(:super_admin)
    ENV["EMAIL"] = super_admin.email
    ENV["ROLE"] = "admin"

    capture_io do
      assert_raises(SystemExit) { Rake::Task["admin:grant"].invoke }
    end

    assert super_admin.reload.super_admin?
  end

  test "最高管理者が複数いる場合は1人を解除できる" do
    @user.change_role!(:super_admin)
    ENV["EMAIL"] = users(:super_admin).email

    capture_io { Rake::Task["admin:revoke"].invoke }

    assert users(:super_admin).reload.user?
    assert_equal [ @user.id ], User.super_admin.pluck(:id)
  end

  test "ROLEにadmin・super_admin以外を指定した場合は権限を変更せずエラー終了する" do
    ENV["EMAIL"] = @user.email

    [ "user", "owner", "", "ADMIN" ].each do |role|
      Rake::Task["admin:grant"].reenable
      ENV["ROLE"] = role

      _output, error_output = capture_io do
        assert_raises(SystemExit) { Rake::Task["admin:grant"].invoke }
      end

      assert_includes error_output, "ROLEにはadminまたはsuper_adminを指定してください"
      assert @user.reload.user?
    end
  end

  test "メールアドレスの大文字や前後の空白を無視して既存ユーザーを指定できる" do
    ENV["EMAIL"] = "  #{@user.email.upcase}  "

    capture_io { Rake::Task["admin:grant"].invoke }

    assert @user.reload.admin?
  end

  test "指定したユーザーだけの権限を変更する" do
    other_user = users(:two)
    ENV["EMAIL"] = @user.email

    capture_io { Rake::Task["admin:grant"].invoke }

    assert @user.reload.admin?
    assert other_user.reload.user?
  end

  test "存在しないユーザーを指定した場合はユーザーを作成せずエラー終了する" do
    ENV["EMAIL"] = "not-found@example.com"

    _output, error_output = capture_io do
      assert_no_difference([ "User.count", "User.where.not(role: :user).count" ]) do
        assert_raises(SystemExit) { Rake::Task["admin:grant"].invoke }
      end
    end

    assert_includes error_output, "指定したメールアドレスのユーザーが見つかりません"
    assert_not_includes error_output, "not-found@example.com"
  end

  test "EMAILを指定しない場合は権限を変更せずエラー終了する" do
    ENV["EMAIL"] = nil

    _output, error_output = capture_io do
      assert_no_difference("User.where.not(role: :user).count") do
        assert_raises(SystemExit) { Rake::Task["admin:grant"].invoke }
      end
    end

    assert_includes error_output, "EMAILを指定してください"
  end

  test "存在しないユーザーの権限解除もエラー終了する" do
    ENV["EMAIL"] = "not-found@example.com"

    capture_io do
      assert_raises(SystemExit) { Rake::Task["admin:revoke"].invoke }
    end
  end

  test "実行結果とログにメールアドレスを出力しない" do
    ENV["EMAIL"] = @user.email

    log = StringIO.new
    original_logger = Rails.logger

    begin
      Rails.logger = ActiveSupport::Logger.new(log)
      output, error_output = capture_io { Rake::Task["admin:grant"].invoke }
    ensure
      Rails.logger = original_logger
    end

    assert @user.reload.admin?
    assert_not_includes output, @user.email
    assert_not_includes error_output, @user.email
    assert_not_includes log.string, @user.email
  end

  private

  def legacy_admin_column(user)
    User.where(id: user.id).pick(:admin)
  end
end
