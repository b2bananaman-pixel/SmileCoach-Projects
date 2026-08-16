require "test_helper"

class PracticeThemesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @practice_theme = PracticeTheme.create!(
      name: "家電",
      description: "家電に関する接客練習"
    )
  end

  test "should get index" do
    get practice_themes_url

    assert_response :success
    assert_select "h1", "練習テーマを選択"
    assert_select "h2", "家電"
  end

  test "should get selected practice theme" do
    get practice_theme_url(@practice_theme)

    assert_response :success
    assert_select "h1", "接客練習"
    assert_select "h2", "練習テーマ：家電"
    assert_select "p", "家電に関する接客練習"
    assert_select "h3", "お客様像・接客条件"
    assert_select "#recording-status", "停止中"
    assert_select "#start-recording", "録画開始"
    assert_select "#stop-recording", "録画停止"
    assert_select "#start-recording:not([disabled])"
    assert_select "#stop-recording[disabled]"
  end
end
