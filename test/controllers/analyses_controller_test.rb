require "test_helper"

class AnalysesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @analysis = analyses(:one)
  end

  test "ログインユーザー自身の分析結果を表示できる" do
    sign_in @user

    get analysis_path(@analysis)

    assert_response :success
    assert_select "body"
  end

  test "他ユーザーの分析結果は表示できない" do
    sign_in @user

    other_analysis = analyses(:two)

    get analysis_path(other_analysis)

    assert_response :not_found
  end

  test "未ログインの場合はログイン画面へリダイレクトされる" do
    get analysis_path(@analysis)

    assert_redirected_to new_user_session_path
  end

  test "録音データがある場合は再生UIが表示される" do
    sign_in @user

    @analysis.practice.audio.attach(
      io: StringIO.new("fake audio data"),
      filename: "practice.webm",
      content_type: "audio/webm"
    )

    get analysis_path(@analysis)

    assert_response :success
    assert_select "audio[controls]"
  end

  test "録音データがない場合も正常に表示される" do
    sign_in @user

    get analysis_path(@analysis)

    assert_response :success
    assert_select "body"
    assert_select "audio", count: 0
  end

  test "AIコメントがない場合はフォールバックメッセージが表示される" do
    sign_in @user

    @analysis.update!(ai_comment: nil)

    get analysis_path(@analysis)

    assert_response :success
    assert_select "h2", text: "今回の改善ポイント"
    assert_select "p", text: "今回の分析結果を確認して、次回の接客練習に活かしましょう。"
  end

  test "笑顔スコアを保存できる" do
    sign_in @user

    patch smile_score_analysis_path(@analysis),
          params: { smile_score: 60 },
          as: :json

    assert_response :success
    assert_equal 60, @analysis.reload.smile_score
    assert_equal 16, @analysis.reload.total_score
    assert_equal(
      { "smile_score" => 60, "total_score" => 16 },
      response.parsed_body
    )
  end

  test "笑顔を分析できない場合は笑顔スコアを保存せず3項目平均で総合スコアを保存する" do
    sign_in @user

    patch smile_score_analysis_path(@analysis),
          params: { smile_score: nil },
          as: :json

    assert_response :success
    assert_nil @analysis.reload.smile_score
    assert_equal 1, @analysis.reload.total_score
    assert_equal(
      { "smile_score" => nil, "total_score" => 1 },
      response.parsed_body
    )
  end

  test "他ユーザーの笑顔スコアは更新できない" do
    sign_in @user

    other_analysis = analyses(:two)

    patch smile_score_analysis_path(other_analysis),
          params: { smile_score: 60 },
          as: :json

    assert_response :not_found
  end

  test "笑顔スコアが0から100の範囲外の場合は保存しない" do
    sign_in @user

    original_score = @analysis.smile_score

    patch smile_score_analysis_path(@analysis),
          params: { smile_score: 101 },
          as: :json

    assert_response :unprocessable_entity
    assert_equal original_score, @analysis.reload.smile_score
  end
end
