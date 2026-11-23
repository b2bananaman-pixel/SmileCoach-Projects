require "test_helper"

class LoginPageTest < ActionDispatch::IntegrationTest
  test "ログイン画面にトップ画面と共通のデザインとログインフォームが表示される" do
    get new_user_session_path

    assert_response :success
    assert_select "h1", text: /AIと楽しくロープレしながら/
    assert_select "img[data-brand-smile-icon]"
    assert_select "img[data-brand-characters]"
    assert_select "form[action='#{user_session_path}']" do
      assert_select "input[type='email'][name='user[email]'][autofocus]"
      assert_select "input[type='password'][name='user[password]']"
      assert_select "input[type='checkbox'][name='user[remember_me]']"
    end
    assert_select "a[href='#{new_user_password_path}']", text: "パスワードをお忘れの方はこちら"
    assert_select "a[href='#{new_user_registration_path}']", count: 0
    assert_select "[data-invitation-only-note]", text: "新規登録は管理者からの招待制です"
  end

  test "トップ画面のフォームから正しい認証情報でログインできる" do
    user = users(:one)

    get root_path
    assert_select "form[action='#{user_session_path}']"

    post user_session_path, params: { user: { email: user.email, password: "password" } }

    assert_redirected_to root_path
    follow_redirect!
    assert_select "[data-mypage-welcome]", text: "#{user.name}さん、おかえりなさい！"
    assert_select "a[data-start-practice-link][href='#{practice_categories_path}']"
  end

  test "認証に失敗するとログイン画面にエラーが表示され、入力したメールアドレスが残る" do
    user = users(:one)

    post user_session_path, params: { user: { email: user.email, password: "wrong_password" } }

    assert_response :unprocessable_content
    assert_select "div.alert", text: "メールアドレスまたはパスワードが違います。"
    assert_select "form[action='#{user_session_path}'] input[name='user[email]'][value='#{user.email}']"
  end

  test "ログイン画面からパスワード再設定画面へ移動でき、新規登録は招待制と案内する" do
    get new_user_session_path
    assert_select "a[href='#{new_user_registration_path}']", count: 0
    assert_select "a[href='#{new_user_password_path}']"

    get new_user_password_path
    assert_response :success
    assert_select "h2", text: "パスワードをお忘れですか？"
    # Devise共通のリンクにも、自由登録へのリンクを表示しない
    assert_select "a[href='#{new_user_registration_path}']", count: 0
    assert_select "[data-invitation-only-note]", text: "新規登録は管理者からの招待制です"
  end

  test "ログイン済みユーザーは練習カテゴリ選択画面へ進める" do
    user = users(:one)
    post user_session_path, params: { user: { email: user.email, password: "password" } }

    get practice_categories_path

    assert_response :success
  end
end
