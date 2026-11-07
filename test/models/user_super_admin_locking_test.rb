require "test_helper"

# 最後の最高管理者の保護が、PostgreSQLの行ロック（SELECT ... FOR UPDATE）により同時実行でも守られることを確認する
#
# スレッドごとに別のDB接続を使うため、トランザクションテストを無効にして実際にコミットする。
# 他のテストに影響しないよう、作成したユーザーは削除し、フィクスチャの最高管理者の権限は元に戻す。
class UserSuperAdminLockingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  LOCK_WAIT_SECONDS = 0.5
  THREAD_TIMEOUT_SECONDS = 10

  setup do
    @fixture_super_admin_id = users(:super_admin).id
    @created_user_ids = []

    # 最高管理者の人数をテストごとに決めるため、フィクスチャの最高管理者は管理者にしておく
    User.where(id: @fixture_super_admin_id).update_all(role: User.roles[:admin])
  end

  teardown do
    User.where(id: @created_user_ids).delete_all
    User.where(id: @fixture_super_admin_id).update_all(role: User.roles[:super_admin], admin: true)
  end

  test "最高管理者が0人の場合はロック対象が0件でもエラーにならず、最初の最高管理者を設定できる" do
    user = create_user(:user)

    assert_equal [], User.transaction { User.lock_super_admin_ids }

    user.change_role!(:super_admin)

    assert_equal [ user.id ], super_admin_ids
  end

  test "最高管理者が0人の場合に2人を同時に昇格しても、どちらも最高管理者になる" do
    first = create_user(:user)
    second = create_user(:user)

    results = run_concurrently(
      -> { User.find(first.id).change_role!(:super_admin) },
      -> { User.find(second.id).change_role!(:super_admin) }
    )

    assert_equal [ :ok, :ok ], results
    assert_equal [ first.id, second.id ].sort, super_admin_ids
  end

  test "最高管理者が1人の場合は、降格・解除・削除のいずれもできない" do
    super_admin = create_user(:super_admin)

    [ :admin, :user ].each do |role|
      assert_raises(ActiveRecord::RecordNotSaved) { User.find(super_admin.id).change_role!(role) }
    end
    assert_not User.find(super_admin.id).destroy

    assert_equal [ super_admin.id ], super_admin_ids
  end

  test "最高管理者が2人の場合は、1人を降格できる" do
    first = create_user(:super_admin)
    second = create_user(:super_admin)

    User.find(first.id).change_role!(:admin)

    assert_equal [ second.id ], super_admin_ids
  end

  test "ロックを保持している間、他の権限変更は待たされ、解放後に最新の人数で判定される" do
    first = create_user(:super_admin)
    second = create_user(:super_admin)
    release = Queue.new
    locked = Queue.new

    # 1つ目のトランザクションで最高管理者の行をロックし、合図があるまで保持してから1人目を降格する
    holder = Thread.new do
      capture_result do
        User.transaction do
          User.lock_super_admin_ids
          locked << true
          release.pop
          User.find(first.id).change_role!(:admin)
        end
      end
    end
    locked.pop

    waiter = Thread.new { capture_result { User.find(second.id).change_role!(:admin) } }

    # ロックが保持されている間、2人目の降格は完了しない
    sleep LOCK_WAIT_SECONDS
    assert waiter.alive?, "ロックの解放前に2人目の降格が完了した"
    assert_equal [ first.id, second.id ].sort, super_admin_ids

    release << true

    # 1人目の降格がコミットされた後は2人目が最後の最高管理者になるため、2人目の降格は拒否される
    assert_equal :ok, join(holder)
    assert_equal ActiveRecord::RecordNotSaved, join(waiter)
    assert_equal [ second.id ], super_admin_ids
  end

  test "最高管理者が2人の場合に2人を同時に降格しても、1人は最高管理者として残る" do
    first = create_user(:super_admin)
    second = create_user(:super_admin)

    results = run_concurrently(
      -> { User.find(first.id).change_role!(:admin) },
      -> { User.find(second.id).change_role!(:user) }
    )

    assert_equal 1, results.count(:ok)
    assert_equal 1, results.count(ActiveRecord::RecordNotSaved)
    assert_equal 1, super_admin_ids.size
  end

  test "最高管理者が2人の場合に2人を同時に削除しても、1人は最高管理者として残る" do
    first = create_user(:super_admin)
    second = create_user(:super_admin)

    results = run_concurrently(
      -> { User.find(first.id).destroy || :aborted },
      -> { User.find(second.id).destroy || :aborted }
    )

    assert_equal 1, results.count(:aborted)
    assert_equal 1, super_admin_ids.size
    assert_equal 1, User.uncached { User.where(id: [ first.id, second.id ]).count }
  end

  test "最高管理者が2人の場合に降格と削除を同時に実行しても、1人は最高管理者として残る" do
    first = create_user(:super_admin)
    second = create_user(:super_admin)

    results = run_concurrently(
      -> { User.find(first.id).change_role!(:admin) },
      -> { User.find(second.id).destroy || :aborted }
    )

    assert_equal 1, results.count { |result| [ ActiveRecord::RecordNotSaved, :aborted ].include?(result) }
    assert_equal 1, super_admin_ids.size
  end

  test "最高管理者が3人の場合に全員を同時に降格しても、デッドロックせず1人が残る" do
    super_admins = Array.new(3) { create_user(:super_admin) }

    results = run_concurrently(*super_admins.map { |user| -> { User.find(user.id).change_role!(:admin) } })

    assert_equal 2, results.count(:ok)
    assert_equal 1, results.count(ActiveRecord::RecordNotSaved)
    assert_equal 1, super_admin_ids.size
  end

  private

  def create_user(role)
    sequence = @created_user_ids.size + 1
    user = User.create!(
      name: "ロック確認ユーザー#{sequence}",
      email: "lock-test-#{sequence}-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: role
    )
    @created_user_ids << user.id
    user
  end

  # 他のスレッド（別接続）でコミットした結果を確認するため、クエリキャッシュを使わずにDBから読み直す
  def super_admin_ids
    User.uncached { User.where(id: @created_user_ids).super_admin.order(:id).pluck(:id) }
  end

  # 各処理を別スレッド・別接続で同時に開始し、結果（:ok・中止・例外クラス）を返す
  def run_concurrently(*operations)
    start = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        start.pop
        capture_result(&operation)
      end
    end

    operations.size.times { start << true }
    threads.map { |thread| join(thread) }
  end

  def capture_result
    ActiveRecord::Base.connection_pool.with_connection do
      result = yield
      result == :aborted ? :aborted : :ok
    end
  rescue StandardError => e
    e.class
  end

  def join(thread)
    assert thread.join(THREAD_TIMEOUT_SECONDS), "スレッドが#{THREAD_TIMEOUT_SECONDS}秒以内に終了しなかった（デッドロックの可能性）"
    thread.value
  end
end
