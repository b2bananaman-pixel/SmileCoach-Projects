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
    assert_select "a[href='#{new_user_registration_path}']", text: "新規登録（無料）"
  end

  test "トップ画面のフォームから正しい認証情報でログインできる" do
    user = users(:one)

    get root_path
    assert_select "form[action='#{user_session_path}']"

    post user_session_path, params: { user: { email: user.email, password: "password" } }

    assert_redirected_to root_path
    follow_redirect!
    assert_select "a[data-start-practice-link][href='#{practice_themes_path}']"
  end

  test "認証に失敗するとログイン画面にエラーが表示され、入力したメールアドレスが残る" do
    user = users(:one)

    post user_session_path, params: { user: { email: user.email, password: "wrong_password" } }

    assert_response :unprocessable_content
    assert_select "div.alert", text: "メールアドレスまたはパスワードが違います。"
    assert_select "form[action='#{user_session_path}'] input[name='user[email]'][value='#{user.email}']"
  end

  test "ログイン画面から新規登録画面とパスワード再設定画面へ移動できる" do
    get new_user_session_path
    assert_select "a[href='#{new_user_registration_path}']"
    assert_select "a[href='#{new_user_password_path}']"

    get new_user_registration_path
    assert_response :success
    assert_select "h2", text: "新規登録"

    get new_user_password_path
    assert_response :success
    assert_select "h2", text: "パスワードをお忘れですか？"
  end

  test "ログイン済みユーザーは練習テーマ選択画面へ進める" do
    user = users(:one)
    post user_session_path, params: { user: { email: user.email, password: "password" } }

    get practice_themes_path

    assert_response :success
  end
end
