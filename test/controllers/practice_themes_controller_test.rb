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
    assert_select "h1", "家電"
    assert_select "p", "家電に関する接客練習"
  end
end
