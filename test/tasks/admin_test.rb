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
  end

  teardown do
    ENV["EMAIL"] = @original_email
  end

  test "admin:grantで既存ユーザーに管理者権限を付与する" do
    ENV["EMAIL"] = @user.email

    output, = capture_io { Rake::Task["admin:grant"].invoke }

    assert @user.reload.admin?
    assert_includes output, "ユーザーID #{@user.id} に管理者権限を付与しました（admin: true）"
  end

  test "admin:revokeで既存ユーザーの管理者権限を解除する" do
    @user.update!(admin: true)
    ENV["EMAIL"] = @user.email

    output, = capture_io { Rake::Task["admin:revoke"].invoke }

    assert_not @user.reload.admin?
    assert_includes output, "ユーザーID #{@user.id} の管理者権限を解除しました（admin: false）"
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
    assert_not other_user.reload.admin?
  end

  test "存在しないユーザーを指定した場合はユーザーを作成せずエラー終了する" do
    ENV["EMAIL"] = "not-found@example.com"

    _output, error_output = capture_io do
      assert_no_difference([ "User.count", "User.where(admin: true).count" ]) do
        assert_raises(SystemExit) { Rake::Task["admin:grant"].invoke }
      end
    end

    assert_includes error_output, "指定したメールアドレスのユーザーが見つかりません"
    assert_not_includes error_output, "not-found@example.com"
  end

  test "EMAILを指定しない場合は権限を変更せずエラー終了する" do
    ENV["EMAIL"] = nil

    _output, error_output = capture_io do
      assert_no_difference("User.where(admin: true).count") do
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
end
