require "test_helper"

class Admin::InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @super_admin = users(:super_admin)
    @user = users(:two)
  end

  test "管理者と最高管理者は招待一覧と発行画面を表示できる" do
    [ @admin, @super_admin ].each do |manager|
      sign_in manager

      get admin_invitations_path
      assert_response :success
      assert_select "[data-admin-invitations] h1", text: "ユーザー招待"

      get new_admin_invitation_path
      assert_response :success
      assert_select "[data-admin-invitation-form] input[type=email][name='invitation[email]']"

      sign_out manager
    end
  end

  test "発行画面のフォームは、発行結果をリダイレクトせずに表示するためTurboを使わずに送信する" do
    sign_in @admin

    get new_admin_invitation_path

    assert_select "form[action=?][method=post][data-turbo=false]", admin_invitations_path
  end

  test "管理者は招待リンクを発行でき、発行直後の画面にだけ招待リンクを表示する" do
    sign_in @admin

    assert_difference("Invitation.count", 1) do
      post admin_invitations_path, params: { invitation: { email: "  New.Member@Example.com " } }
    end

    assert_response :created
    invitation = Invitation.last
    assert_equal "new.member@example.com", invitation.email
    assert_equal @admin, invitation.invited_by

    url = css_select("[data-invitation-url]").first["value"]
    token = Rack::Utils.parse_query(URI.parse(url).query).fetch("invitation_token")
    assert_equal new_user_registration_url(invitation_token: token), url
    assert_equal Invitation.digest(token), invitation.token_digest
    assert_select "[data-invitation-email]", text: "new.member@example.com"

    # 一覧・発行画面には招待リンクを再表示しない
    get admin_invitations_path
    assert_not_includes response.body, token
    assert_select "[data-invitation-id='#{invitation.id}'][data-invitation-status=pending]"

    get new_admin_invitation_path
    assert_not_includes response.body, token
  end

  test "招待リンクを表示する画面は、キャッシュに保存させずRefererも送らない" do
    sign_in @admin

    post admin_invitations_path, params: { invitation: { email: "new-member@example.com" } }

    assert_response :created
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "招待リンクのトークンと招待するメールアドレスをログに出さない" do
    sign_in @admin
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    post admin_invitations_path, params: { invitation: { email: "new-member@example.com" } }
    token = Rack::Utils.parse_query(URI.parse(css_select("[data-invitation-url]").first["value"]).query).fetch("invitation_token")

    assert_not_includes log.string, token
    assert_not_includes log.string, Invitation.last.token_digest
    assert_not_includes log.string, "new-member@example.com"
  ensure
    Rails.logger = original_logger
  end

  test "発行者・トークン・有効期限・使用状態はパラメータで指定できない" do
    sign_in @admin

    post admin_invitations_path, params: {
      invitation: {
        email: "new-member@example.com",
        invited_by_id: @super_admin.id,
        token_digest: "0" * 64,
        expires_at: 1.year.from_now,
        accepted_at: Time.current,
        accepted_user_id: @user.id,
        revoked_at: Time.current
      }
    }

    assert_response :created
    invitation = Invitation.last
    assert_equal @admin, invitation.invited_by
    assert_not_equal "0" * 64, invitation.token_digest
    assert_in_delta 7.days.from_now, invitation.expires_at, 1.minute
    assert_nil invitation.accepted_at
    assert_nil invitation.accepted_user_id
    assert_nil invitation.revoked_at
  end

  test "形式が正しくないメールアドレスでは発行せず、エラーを表示する" do
    sign_in @admin

    assert_no_difference("Invitation.count") do
      post admin_invitations_path, params: { invitation: { email: "not-an-email" } }
    end

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors]"
    assert_select "[data-invitation-url]", count: 0
  end

  test "登録済みのメールアドレスには発行しない" do
    sign_in @admin

    assert_no_difference("Invitation.count") do
      post admin_invitations_path, params: { invitation: { email: users(:one).email } }
    end

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: "メールアドレスはすでに登録されています"
  end

  test "有効な招待があるメールアドレスには重複して発行しない" do
    sign_in @admin
    post admin_invitations_path, params: { invitation: { email: "new-member@example.com" } }

    assert_no_difference("Invitation.count") do
      post admin_invitations_path, params: { invitation: { email: "new-member@example.com" } }
    end

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: /有効な招待がすでにあります/
  end

  test "招待一覧に状態・有効期限・発行者を表示し、未使用の招待にだけ取り消しボタンを表示する" do
    pending = Invitation.issue(email: "pending@example.com", invited_by: @admin)
    accepted = Invitation.issue(email: "accepted@example.com", invited_by: @super_admin)
    accepted.update!(accepted_at: Time.current, accepted_user: @user)
    expired = nil
    travel_to 8.days.ago do
      expired = Invitation.issue(email: "expired@example.com", invited_by: @admin)
    end
    sign_in @admin

    get admin_invitations_path

    assert_response :success
    assert_select "[data-invitation-id='#{pending.id}']" do
      assert_select ".badge", text: "未使用"
      assert_select "td", text: @admin.name
      assert_select "td", text: I18n.l(pending.expires_at, format: "%Y/%m/%d %H:%M")
      assert_select "form[action=?]", revoke_admin_invitation_path(pending) do |forms|
        assert_includes forms.first["data-turbo-confirm"], "招待を取り消しますか？"
      end
    end
    assert_select "[data-invitation-id='#{accepted.id}'] .badge", text: "使用済み"
    assert_select "[data-invitation-id='#{accepted.id}'] form", count: 0
    assert_select "[data-invitation-id='#{expired.id}'] .badge", text: "期限切れ"
    assert_select "[data-invitation-id='#{expired.id}'] form", count: 0
  end

  test "発行者が削除された招待は、一覧で削除されたユーザーと表示する" do
    issuer = User.create!(name: "削除される管理者", email: "issuer@example.com", password: "password", role: :admin)
    invitation = Invitation.issue(email: "new-member@example.com", invited_by: issuer)
    issuer.destroy!
    sign_in @admin

    get admin_invitations_path

    assert_select "[data-invitation-id='#{invitation.id}'] td", text: "削除されたユーザー"
  end

  test "未使用の招待を取り消せる" do
    invitation = Invitation.issue(email: "new-member@example.com", invited_by: @admin)
    sign_in @super_admin

    patch revoke_admin_invitation_path(invitation)

    assert_redirected_to admin_invitations_path
    assert_response :see_other
    assert_equal "new-member@example.comへの招待を取り消しました。", flash[:notice]
    assert_equal :revoked, invitation.reload.status
  end

  test "使用済み・取り消し済みの招待は取り消せず、エラーを表示する" do
    accepted = Invitation.issue(email: "accepted@example.com", invited_by: @admin)
    accepted.update!(accepted_at: Time.current, accepted_user: @user)
    revoked = Invitation.issue(email: "revoked@example.com", invited_by: @admin)
    revoked.revoke!
    sign_in @admin

    [ accepted, revoked ].each do |invitation|
      patch revoke_admin_invitation_path(invitation)

      assert_redirected_to admin_invitations_path
      assert_equal Admin::InvitationsController::REVOKE_FAILED_MESSAGE, flash[:alert]
    end
    assert_nil accepted.reload.revoked_at
  end

  test "存在しない招待の取り消しは404を返す" do
    sign_in @admin

    patch revoke_admin_invitation_path(id: Invitation.maximum(:id).to_i + 1)

    assert_response :not_found
  end

  test "一般ユーザーは招待の一覧・発行・取り消しにアクセスできず404を返す" do
    invitation = Invitation.issue(email: "new-member@example.com", invited_by: @admin)
    sign_in @user

    get admin_invitations_path
    assert_response :not_found

    get new_admin_invitation_path
    assert_response :not_found

    assert_no_difference("Invitation.count") do
      post admin_invitations_path, params: { invitation: { email: "other@example.com" } }
    end
    assert_response :not_found

    patch revoke_admin_invitation_path(invitation)
    assert_response :not_found
    assert invitation.reload.usable?
  end

  test "未ログインの場合は招待の一覧・発行・取り消しを行わずログイン画面へリダイレクトする" do
    invitation = Invitation.issue(email: "new-member@example.com", invited_by: @admin)

    get admin_invitations_path
    assert_redirected_to new_user_session_path

    get new_admin_invitation_path
    assert_redirected_to new_user_session_path

    assert_no_difference("Invitation.count") do
      post admin_invitations_path, params: { invitation: { email: "other@example.com" } }
    end
    assert_redirected_to new_user_session_path

    patch revoke_admin_invitation_path(invitation)
    assert_redirected_to new_user_session_path
    assert invitation.reload.usable?
  end

  test "CSRFトークンのない発行・取り消しは拒否する" do
    invitation = Invitation.issue(email: "new-member@example.com", invited_by: @admin)
    sign_in @admin

    with_forgery_protection do
      assert_no_difference("Invitation.count") do
        post admin_invitations_path, params: { invitation: { email: "other@example.com" } }
      end
      assert_response :unprocessable_entity

      patch revoke_admin_invitation_path(invitation)
      assert_response :unprocessable_entity
    end

    assert invitation.reload.usable?
  end

  test "発行画面のフォームのCSRFトークンを使えば招待を発行できる" do
    sign_in @admin

    with_forgery_protection do
      get new_admin_invitation_path
      token = css_select("[data-admin-invitation-form] form input[name=authenticity_token]").first["value"]

      assert_difference("Invitation.count", 1) do
        post admin_invitations_path, params: { authenticity_token: token, invitation: { email: "new-member@example.com" } }
      end
    end

    assert_response :created
  end

  test "招待の発行は既存の自由登録を停止しない（PR 1の段階）" do
    get new_user_registration_path

    assert_response :success
    assert_select "h2", text: "新規登録"
  end

  private

  # テスト環境では無効にしているCSRF対策を、ブロックの中だけ有効にする
  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
