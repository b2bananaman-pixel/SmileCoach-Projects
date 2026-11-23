require "test_helper"

# 招待制の新規登録（Issue #90）
class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  INVALID_MESSAGE = "招待リンクが無効か有効期限が切れています".freeze
  INVITED_EMAIL = "invited-member@example.com".freeze

  setup do
    @admin = users(:admin)
  end

  # ---- 招待がない場合 ----

  test "招待なしで新規登録画面を開くと、ログイン画面へ移動して招待が無効と表示する" do
    get new_user_registration_path

    assert_rejected
    follow_redirect!
    assert_response :success
    assert_select "div.alert-danger", text: INVALID_MESSAGE
    assert_select "form[action='#{user_registration_path}']", count: 0
  end

  test "招待なしでPOST /usersを直接送信しても登録できない" do
    assert_no_difference("User.count") do
      post user_registration_path, params: { user: signup_params(email: "direct-post@example.com") }
    end

    assert_rejected
    assert_not User.exists?(email: "direct-post@example.com")
  end

  # ---- 招待リンクの受け取り ----

  test "招待リンクを開くと、招待IDだけをセッションに保存し、トークンを含まないURLへ303でリダイレクトする" do
    invitation = issue

    get new_user_registration_path(invitation_token: invitation.token)

    assert_response :see_other
    assert_redirected_to new_user_registration_path
    assert_nil URI.parse(response.location).query
    assert_equal invitation.id, session["invitation_id"]
    assert_not_includes session.to_hash.to_s, invitation.token
    assert_not_includes session.to_hash.to_s, invitation.token_digest
  end

  test "招待リンクからリダイレクトした後の登録フォームに、招待先のメールアドレスを読み取り専用で表示する" do
    open_signup_form(issue)

    assert_response :success
    assert_select "h2", text: "新規登録"
    assert_select "form[action='#{user_registration_path}']" do
      assert_select "input[name='user[email]'][readonly][value='#{INVITED_EMAIL}'][data-invitation-email]"
      assert_select "input[name='user[name]']"
      assert_select "input[type='password'][name='user[password]']"
      assert_select "input[type='password'][name='user[password_confirmation]']"
    end
  end

  test "無効・期限切れ・使用済み・取り消し済みの招待リンクは、同じメッセージでログイン画面へ移動する" do
    expired = travel_to(8.days.ago) { issue("expired@example.com") }
    accepted = issue("accepted@example.com")
    accepted.update!(accepted_at: Time.current)
    revoked = issue("revoked@example.com")
    revoked.revoke!

    [ "invalid-token", "", expired.token, accepted.token, revoked.token ].each do |token|
      get new_user_registration_path(invitation_token: token)

      assert_rejected
      assert_nil session["invitation_id"]
    end
  end

  test "文字列以外の招待トークンも、エラーにせずログイン画面へ移動する" do
    invitation = issue

    get "#{new_user_registration_path}?invitation_token[]=#{invitation.token}"

    assert_rejected
    assert_nil session["invitation_id"]
  end

  test "無効な招待リンクを開くと、以前に開いた有効な招待もセッションから削除する" do
    open_signup_form(issue)

    get new_user_registration_path(invitation_token: "invalid-token")

    assert_rejected
    assert_nil session["invitation_id"]
  end

  test "ログイン済みの場合は招待リンクを開いても登録画面を表示せず、招待を使用しない" do
    invitation = issue
    sign_in users(:one)

    get new_user_registration_path(invitation_token: invitation.token)

    assert_redirected_to root_path
    assert_nil session["invitation_id"]
    assert invitation.reload.usable?
  end

  # ---- 登録 ----

  test "有効な招待で登録すると、招待先のメールアドレスで一般ユーザーを作成してログインし、招待を使用済みにする" do
    invitation = issue
    open_signup_form(invitation)

    assert_difference("User.count", 1) do
      post user_registration_path, params: { user: signup_params }
    end

    user = User.find_by!(email: INVITED_EMAIL)
    assert_equal "招待ユーザー", user.name
    assert user.user?
    invitation.reload
    assert_equal :accepted, invitation.status
    assert_equal user, invitation.accepted_user
    assert_nil session["invitation_id"]

    assert_redirected_to root_path
    follow_redirect!
    assert_select "[data-mypage-welcome]", text: "招待ユーザーさん、おかえりなさい！"
  end

  test "送信されたメールアドレスは使わず、招待先のメールアドレスで登録する" do
    open_signup_form(issue)

    assert_difference("User.count", 1) do
      post user_registration_path, params: { user: signup_params(email: "tampered@example.com") }
    end

    assert User.exists?(email: INVITED_EMAIL)
    assert_not User.exists?(email: "tampered@example.com")
  end

  test "role・admin等を送信しても一般ユーザーとして登録する" do
    open_signup_form(issue)

    post user_registration_path, params: { user: signup_params.merge(role: "super_admin", admin: true, super_admin: true) }

    user = User.find_by!(email: INVITED_EMAIL)
    assert user.user?
    assert_equal false, User.where(id: user.id).pick(:admin)
  end

  test "入力に誤りがある場合は、招待を使用せずにエラーを表示し、そのまま再入力して登録できる" do
    invitation = issue
    open_signup_form(invitation)

    assert_no_difference("User.count") do
      post user_registration_path, params: { user: signup_params(name: "", password_confirmation: "different") }
    end

    assert_response :unprocessable_entity
    assert_select "form[action='#{user_registration_path}'] input[name='user[email]'][readonly][value='#{INVITED_EMAIL}']"
    assert invitation.reload.usable?
    assert_equal invitation.id, session["invitation_id"]

    assert_difference("User.count", 1) do
      post user_registration_path, params: { user: signup_params }
    end
    assert_equal :accepted, invitation.reload.status
  end

  test "登録フォームを開いた後に招待が取り消された・期限が切れた場合は、登録せずログイン画面へ移動する" do
    revoked = issue("revoked@example.com")
    open_signup_form(revoked)
    revoked.revoke!

    assert_no_difference("User.count") do
      post user_registration_path, params: { user: signup_params }
    end
    assert_rejected
    assert_nil session["invitation_id"]

    expiring = issue("expiring@example.com")
    open_signup_form(expiring)

    travel_to expiring.expires_at + 1.second do
      get new_user_registration_path
      assert_rejected

      assert_no_difference("User.count") do
        post user_registration_path, params: { user: signup_params }
      end
      assert_rejected
    end
  end

  test "同じ招待で2回登録できない（別のブラウザで同じ招待リンクを開いていた場合を含む）" do
    invitation = issue
    other_browser = open_session
    other_browser.get new_user_registration_path(invitation_token: invitation.token)
    other_browser.follow_redirect!

    open_signup_form(invitation)
    post user_registration_path, params: { user: signup_params }
    assert_equal :accepted, invitation.reload.status

    assert_no_difference("User.count") do
      other_browser.post user_registration_path, params: { user: signup_params(name: "2人目") }
    end
    assert_equal 303, other_browser.response.status
    assert_equal new_user_session_url, other_browser.response.location
    assert_equal INVALID_MESSAGE, other_browser.flash[:alert]

    # 使用済みの招待リンクを開き直しても利用できない
    other_browser.get new_user_registration_path(invitation_token: invitation.token)
    assert_equal new_user_session_url, other_browser.response.location
  end

  # ---- ヘッダー・ログ・CSRF ----

  test "招待の受け取り・登録画面・登録の各レスポンスは、キャッシュに保存させず、Referrer-Policyをsame-originにする" do
    invitation = issue

    get new_user_registration_path(invitation_token: invitation.token)
    assert_invitation_headers

    follow_redirect!
    assert_invitation_headers

    post user_registration_path, params: { user: signup_params(name: "") }
    assert_response :unprocessable_entity
    assert_invitation_headers

    post user_registration_path, params: { user: signup_params }
    assert_redirected_to root_path
    assert_invitation_headers

    sign_out :user
    get new_user_registration_path
    assert_rejected
    assert_invitation_headers
  end

  test "招待トークンとダイジェストをログに出さない" do
    invitation = issue
    log = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    get new_user_registration_path(invitation_token: invitation.token)
    follow_redirect!
    post user_registration_path, params: { user: signup_params }

    assert_includes log.string, "invitation_token=[FILTERED]"
    assert_not_includes log.string, invitation.token
    assert_not_includes log.string, invitation.token_digest
  ensure
    Rails.logger = original_logger
  end

  test "CSRF保護とOrigin検証を有効にした状態で、登録フォームのCSRFトークンを使えば登録できる" do
    invitation = issue

    with_forgery_protection do
      assert ActionController::Base.forgery_protection_origin_check

      token = signup_form_token(invitation)
      assert_difference("User.count", 1) do
        post user_registration_path, params: { authenticity_token: token, user: signup_params },
                                     headers: { "Origin" => same_origin }
      end
    end

    assert_redirected_to root_path
    assert_equal :accepted, invitation.reload.status
  end

  test "CSRF保護を有効にした状態で、CSRFトークンのない送信と、Originがnullまたは他のサイトの送信は拒否し、招待を使用しない" do
    invitation = issue

    with_forgery_protection do
      token = signup_form_token(invitation)

      assert_no_difference("User.count") do
        post user_registration_path, params: { user: signup_params }, headers: { "Origin" => same_origin }
      end
      assert_response :unprocessable_entity

      [ "null", "https://attacker.example" ].each do |origin|
        assert_no_difference("User.count") do
          post user_registration_path, params: { authenticity_token: token, user: signup_params },
                                       headers: { "Origin" => origin }
        end
        assert_response :unprocessable_entity
      end
    end

    assert invitation.reload.usable?
  end

  # ---- 既存ユーザー ----

  test "既存ユーザーはこれまでどおりログインし、アカウント編集画面を表示できる" do
    user = users(:one)

    post user_session_path, params: { user: { email: user.email, password: "password" } }
    assert_redirected_to root_path

    get edit_user_registration_path
    assert_response :success
    assert_select "input[name='user[email]'][value='#{user.email}']"
    assert_select "input[name='user[email]'][readonly]", count: 0
  end

  private

  def issue(email = INVITED_EMAIL)
    Invitation.issue(email: email, invited_by: @admin)
  end

  def signup_params(name: "招待ユーザー", email: INVITED_EMAIL, password_confirmation: "password")
    { name: name, email: email, password: "password", password_confirmation: password_confirmation }
  end

  # 招待リンクを開き、リダイレクト先の登録フォームを表示する
  def open_signup_form(invitation)
    get new_user_registration_path(invitation_token: invitation.token)
    assert_redirected_to new_user_registration_path
    follow_redirect!
  end

  def signup_form_token(invitation)
    open_signup_form(invitation)
    css_select("form[action='#{user_registration_path}'] input[name=authenticity_token]").first["value"]
  end

  def assert_rejected
    assert_response :see_other
    assert_redirected_to new_user_session_path
    assert_equal INVALID_MESSAGE, flash[:alert]
  end

  # no-referrerはTurboで移動した後も文書に残り、通常のフォーム送信でOriginが"null"になるため使わない（PR #136）
  def assert_invitation_headers
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "same-origin", response.headers["Referrer-Policy"]
  end

  # 統合テストのリクエスト先と同じOrigin
  def same_origin
    "http://www.example.com"
  end

  # テスト環境では無効にしているCSRF対策を、ブロックの中だけ有効にする
  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
