require "test_helper"

# 同じ招待で同時に登録した場合に、1件だけ成功することを別々のDB接続で確認する（Issue #90）
#
# 行ロックの待ち合わせはテスト用のトランザクションの中では確認できないため、このテストだけトランザクションを使わず、
# 作成したデータはteardownで削除する。
class InvitationConcurrentAcceptTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  EMAIL = "concurrent-signup@example.com".freeze

  setup do
    @invitation = Invitation.issue(email: EMAIL, invited_by: users(:admin))
  end

  teardown do
    Invitation.where(email: EMAIL).delete_all
    User.where(email: EMAIL).delete_all
  end

  test "同じ招待で同時に登録しても、ユーザーは1人だけ作成され、もう一方は招待を利用できない" do
    start = Queue.new
    results = []
    lock = Mutex.new

    threads = Array.new(2) do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.pop
          invitation = Invitation.find(@invitation.id)
          user = User.new(name: "同時登録#{index}", password: "password", password_confirmation: "password")

          result = begin
            invitation.accept_with(user) ? :accepted : :invalid
          rescue Invitation::NotUsableError
            :not_usable
          end
          lock.synchronize { results << result }
        end
      end
    end

    2.times { start << true }
    threads.each(&:join)

    assert_equal %i[accepted not_usable], results.sort
    assert_equal 1, User.where(email: EMAIL).count

    @invitation.reload
    assert_equal :accepted, @invitation.status
    assert_equal User.find_by!(email: EMAIL), @invitation.accepted_user
  end
end
