require "test_helper"

class PracticeThemesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @practice_theme = PracticeTheme.create!(
      name: "家電の提案販売",
      description: "お客様像：冷蔵庫売り場に来店している30代くらいの男女。現在使用している冷蔵庫が古くなり、買い替えを検討している。\n\n接客条件：\n① お客様へ明るく声掛けをする\n② 現在の利用状況を確認する\n③ お客様に合ったサービスを提案する"
    )
  end

  test "should get index" do
    get practice_themes_url

    assert_response :success
    assert_select "h1", "練習テーマを選択"
    assert_select "h2", "家電の提案販売"
  end

  test "should get selected practice theme" do
    get practice_theme_url(@practice_theme)

    assert_response :success
    assert_select "h1", "接客練習"
    assert_select "h2", "練習テーマ：家電の提案販売"
    assert_select "h3", "👤 お客様像"
    assert_select "h3", "🎯 今回の接客ポイント"
    assert_select "p", /冷蔵庫売り場に来店している30代くらいの男女/
    assert_select "p", /お客様へ明るく声掛けをする/
    assert_select "p", /現在の利用状況を確認する/
    assert_select "p", /お客様に合ったサービスを提案する/
    assert_select "#recording-status", "停止中"
    assert_select "#start-recording", "録画開始"
    assert_select "#stop-recording", "録画停止"
    assert_select "#start-recording:not([disabled])"
    assert_select "#stop-recording[disabled]"
  end
end
