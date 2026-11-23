require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @admin = users(:admin)
  end

  test "招待を発行すると256ビットのトークンを生成し、DBにはSHA-256のダイジェストだけを保存する" do
    invitation = issue("new-member@example.com")

    assert invitation.persisted?
    # 32バイトをURLセーフなBase64にすると、パディングなしで43文字になる
    assert_equal 43, invitation.token.length
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, invitation.token)
    assert_equal OpenSSL::Digest::SHA256.hexdigest(invitation.token), invitation.token_digest

    row = Invitation.connection.select_one("SELECT * FROM invitations WHERE id = #{invitation.id}")
    assert_not row.values.any? { |value| value.to_s.include?(invitation.token) }
  end

  test "毎回異なるトークンを生成する" do
    first = issue("first@example.com")
    second = issue("second@example.com")

    assert_not_equal first.token, second.token
    assert_not_equal first.token_digest, second.token_digest
  end

  test "DBから読み込んだ招待からは生のトークンを取得できず、inspectにもダイジェストを出さない" do
    invitation = issue("new-member@example.com")
    reloaded = Invitation.find(invitation.id)

    assert_nil reloaded.token
    assert_not_includes reloaded.inspect, invitation.token_digest
    assert_not_includes invitation.inspect, invitation.token
  end

  test "有効期限は発行から7日後" do
    travel_to Time.zone.local(2026, 11, 22, 10, 0, 0) do
      invitation = issue("new-member@example.com")

      assert_equal Time.zone.local(2026, 11, 29, 10, 0, 0), invitation.expires_at
    end
  end

  test "メールアドレスは前後の空白を除き小文字にそろえる" do
    invitation = issue("  New.Member@Example.COM  ")

    assert_equal "new.member@example.com", invitation.reload.email
  end

  test "メールアドレスが空・形式不正・長すぎる場合は発行しない" do
    [ "", "   ", "not-an-email", "#{'a' * 250}@example.com" ].each do |email|
      assert_no_difference("Invitation.count") do
        invitation = issue(email)

        assert_not invitation.persisted?, "#{email.inspect}では発行しないこと"
        assert invitation.errors.include?(:email), "#{email.inspect}ではメールアドレスのエラーになること"
      end
    end
  end

  test "登録済みのメールアドレスには発行しない（大文字・小文字の違いを含む）" do
    assert_no_difference("Invitation.count") do
      invitation = issue(users(:one).email.upcase)

      assert invitation.errors.of_kind?(:email, :already_registered)
    end
  end

  test "同じメールアドレスに有効な招待がある場合は重複して発行しない" do
    issue("new-member@example.com")

    assert_no_difference("Invitation.count") do
      invitation = issue("NEW-MEMBER@example.com")

      assert invitation.errors.of_kind?(:email, :already_invited)
    end
  end

  test "同時に発行された場合も、DBの部分一意インデックスで2件目を拒否する" do
    issue("new-member@example.com")

    duplicated = Invitation.new(email: "new-member@example.com", invited_by: @admin)
    duplicated.assign_new_token

    assert_raises(ActiveRecord::RecordNotUnique) { duplicated.save!(validate: false) }
  end

  test "同時発行で一意インデックスに違反した場合は、例外にせずエラーとして返す" do
    issue("new-member@example.com")

    # モデルの重複確認をすり抜けた（同時に発行された）場合を再現する
    racing = Invitation.new(email: "new-member@example.com", invited_by: @admin)
    racing.define_singleton_method(:no_pending_invitation_for_email) { nil }

    result = nil
    assert_no_difference("Invitation.count") do
      Invitation.stub(:new, racing) do
        result = Invitation.issue(email: "new-member@example.com", invited_by: @admin)
      end
    end

    assert_not result.persisted?
    assert result.errors.of_kind?(:email, :already_invited)
  end

  test "取り消した招待のメールアドレスには再発行できる" do
    invitation = issue("new-member@example.com")
    invitation.revoke!

    reissued = issue("new-member@example.com")

    assert reissued.persisted?
    assert_equal :pending, reissued.status
  end

  test "期限切れの未使用の招待があるメールアドレスには再発行でき、古い招待は期限切れのまま利用できない" do
    old = nil
    travel_to 8.days.ago do
      old = issue("new-member@example.com")
    end

    reissued = issue("new-member@example.com")

    assert reissued.persisted?
    old.reload
    assert old.revoked_at.present?
    assert_equal :expired, old.status
    assert_not old.usable?
  end

  test "状態は未使用・使用済み・取り消し済み・期限切れを判定する" do
    pending = issue("pending@example.com")
    accepted = issue("accepted@example.com")
    accepted.update!(accepted_at: Time.current, accepted_user: users(:two))
    revoked = issue("revoked@example.com")
    revoked.revoke!
    expired = nil
    travel_to 8.days.ago do
      expired = issue("expired@example.com")
    end

    assert_equal [ :pending, "未使用", true ], [ pending.status, pending.status_label, pending.usable? ]
    assert_equal [ :accepted, "使用済み", false ], [ accepted.status, accepted.status_label, accepted.usable? ]
    assert_equal [ :revoked, "取り消し済み", false ], [ revoked.status, revoked.status_label, revoked.usable? ]
    assert_equal [ :expired, "期限切れ", false ], [ expired.status, expired.status_label, expired.usable? ]
  end

  test "有効期限の時刻ちょうどで期限切れになる" do
    invitation = issue("new-member@example.com")

    assert invitation.usable?(now: invitation.expires_at - 1.second)
    assert_not invitation.usable?(now: invitation.expires_at)
  end

  test "未使用の招待だけを取り消せる" do
    invitation = issue("new-member@example.com")

    invitation.revoke!

    assert invitation.reload.revoked_at.present?
    assert_equal :revoked, invitation.status
  end

  test "使用済み・取り消し済み・期限切れの招待は取り消せない" do
    accepted = issue("accepted@example.com")
    accepted.update!(accepted_at: Time.current, accepted_user: users(:two))
    revoked = issue("revoked@example.com")
    revoked.revoke!
    expired = nil
    travel_to 8.days.ago do
      expired = issue("expired@example.com")
    end

    [ accepted, revoked, expired ].each do |invitation|
      assert_raises(Invitation::NotRevocableError) { invitation.revoke! }
    end
    assert_nil expired.reload.revoked_at
  end

  test "発行者のアカウントを削除しても招待の履歴は残り、発行者はNULLになる" do
    issuer = User.create!(name: "削除される管理者", email: "issuer@example.com", password: "password", role: :admin)
    invitation = Invitation.issue(email: "new-member@example.com", invited_by: issuer)

    assert_no_difference("Invitation.count") do
      issuer.destroy!
    end

    invitation.reload
    assert_nil invitation.invited_by_id
    assert_equal "new-member@example.com", invitation.email
    assert invitation.usable?
  end

  test "登録したユーザーを削除しても招待の履歴は残り、使用日時も残る" do
    member = User.create!(name: "登録したユーザー", email: "member@example.com", password: "password")
    invitation = issue("other@example.com")
    invitation.update!(accepted_at: Time.current, accepted_user: member)

    member.destroy!

    invitation.reload
    assert_nil invitation.accepted_user_id
    assert invitation.accepted_at.present?
    assert_equal :accepted, invitation.status
  end

  test "DBの制約で、正規化していないメール・不正なダイジェスト・使用と取り消しの両立・使用日時のない登録ユーザーを拒否する" do
    invitation = issue("new-member@example.com")

    # モデルの正規化・検証を通さないよう、SQLで直接更新する
    [
      "email = 'New-Member@example.com'",
      "email = ''",
      "token_digest = 'not-a-digest'",
      "accepted_at = now(), revoked_at = now()",
      "accepted_user_id = #{users(:two).id}",
      "expires_at = created_at - interval '1 second'"
    ].each do |assignment|
      assert_raises(ActiveRecord::StatementInvalid, "#{assignment}はDBの制約で拒否されること") do
        raw_update(invitation, assignment)
      end
    end
  end

  test "1人のユーザーは1つの招待でだけ登録したことになる" do
    first = issue("first@example.com")
    first.update!(accepted_at: Time.current, accepted_user: users(:two))
    second = issue("second@example.com")

    assert_raises(ActiveRecord::RecordNotUnique) do
      raw_update(second, "accepted_at = now(), accepted_user_id = #{users(:two).id}")
    end
  end

  # ---- 新規登録での利用（PR 2） ----

  test "有効な招待のトークンから招待を検索できる" do
    invitation = issue("new-member@example.com")

    assert_equal invitation, Invitation.find_usable_by_token(invitation.token)
  end

  test "不正・空・文字列以外のトークンや、ダイジェストそのものでは招待を検索できない" do
    invitation = issue("new-member@example.com")

    [ "invalid-token", "", nil, [ invitation.token ], { token: invitation.token }, invitation.token_digest ].each do |token|
      assert_nil Invitation.find_usable_by_token(token), "#{token.inspect}で検索できてはいけない"
    end
  end

  test "期限切れ・使用済み・取り消し済みの招待は、トークンからもIDからも検索できない" do
    expired = travel_to(8.days.ago) { issue("expired@example.com") }
    accepted = issue("accepted@example.com")
    accepted.update!(accepted_at: Time.current)
    revoked = issue("revoked@example.com")
    revoked.revoke!

    [ expired, accepted, revoked ].each do |invitation|
      assert_nil Invitation.find_usable_by_token(invitation.token), invitation.email
      assert_nil Invitation.find_usable(invitation.id), invitation.email
    end
  end

  test "存在しない・空の招待IDでは検索できない" do
    assert_nil Invitation.find_usable(nil)
    assert_nil Invitation.find_usable("")
    assert_nil Invitation.find_usable(0)
  end

  test "招待を使って登録すると、招待先のメールアドレスで一般ユーザーを作成し、招待を使用済みにする" do
    invitation = issue("new-member@example.com")
    user = User.new(name: "新規ユーザー", email: "other@example.com", password: "password", password_confirmation: "password")

    travel_to Time.zone.local(2026, 11, 23, 10, 0, 0) do
      assert_difference("User.count", 1) do
        assert invitation.accept_with(user)
      end

      invitation.reload
      assert user.persisted?
      assert_equal "new-member@example.com", user.reload.email
      assert user.user?
      assert_equal user, invitation.accepted_user
      assert_equal Time.zone.local(2026, 11, 23, 10, 0, 0), invitation.accepted_at
      assert_equal :accepted, invitation.status
    end
  end

  test "ユーザーの入力に誤りがある場合は、ユーザーを作成せず招待を未使用のまま残す" do
    invitation = issue("new-member@example.com")
    user = User.new(name: "", password: "password", password_confirmation: "different")

    assert_no_difference("User.count") do
      assert_not invitation.accept_with(user)
    end

    assert_not user.persisted?
    assert user.errors.include?(:name)
    assert user.errors.include?(:password_confirmation)
    assert invitation.reload.usable?
    assert_nil invitation.accepted_user_id
  end

  test "招待先のメールアドレスが登録済みになっていた場合は、ユーザーを作成せず招待を未使用のまま残す" do
    invitation = issue("new-member@example.com")
    users(:one).update!(email: "new-member@example.com")
    user = User.new(name: "新規ユーザー", password: "password", password_confirmation: "password")

    assert_no_difference("User.count") do
      assert_not invitation.accept_with(user)
    end

    assert user.errors.include?(:email)
    assert invitation.reload.usable?
  end

  test "登録の直前に招待が使用済み・取り消し済み・期限切れになっていた場合は、ユーザーを作成しない" do
    accepted = issue("accepted@example.com")
    revoked = issue("revoked@example.com")
    expired = issue("expired@example.com")

    # 別のリクエストで状態が変わった場合を想定し、メモリ上の招待は未使用のまま、DBだけを更新する
    raw_update(accepted, "accepted_at = NOW()")
    raw_update(revoked, "revoked_at = NOW()")

    [ [ accepted, Time.current ], [ revoked, Time.current ], [ expired, expired.expires_at ] ].each do |invitation, now|
      assert invitation.usable?(now: Time.current)
      user = User.new(name: "新規ユーザー", password: "password", password_confirmation: "password")

      assert_no_difference("User.count") do
        assert_raises(Invitation::NotUsableError) { invitation.accept_with(user, now: now) }
      end
      assert_not user.persisted?
    end
  end

  test "同じ招待で2回登録することはできない（読み込み済みの古い招待を使っても行ロックで再確認する）" do
    invitation = issue("new-member@example.com")
    stale = Invitation.find(invitation.id)

    assert invitation.accept_with(User.new(name: "1人目", password: "password", password_confirmation: "password"))

    assert_no_difference("User.count") do
      assert_raises(Invitation::NotUsableError) do
        stale.accept_with(User.new(name: "2人目", password: "password", password_confirmation: "password"))
      end
    end
  end

  private

  def issue(email)
    Invitation.issue(email: email, invited_by: @admin)
  end

  # 制約違反の後もテストを続けられるよう、セーブポイントの中で実行する
  def raw_update(invitation, assignment)
    Invitation.transaction(requires_new: true) do
      Invitation.connection.execute("UPDATE invitations SET #{assignment} WHERE id = #{invitation.id}")
    end
  end
end
