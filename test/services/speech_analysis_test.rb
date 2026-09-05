require "test_helper"

class SpeechAnalysisTest < ActiveSupport::TestCase
  test "モーラ数を計算できる" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちはきょうはいいてんきですね",
      duration: 5.0
    )

    assert_equal 16, analysis.mora_count
  end

  test "小さい文字を含む単語を正しくモーラ数として計算できる" do
    analysis = SpeechAnalysis.new(
      transcription: "きょう",
      duration: 1.0
    )

    assert_equal 2, analysis.mora_count
  end

  test "文字数ではなくモーラ数と録音時間から話速を計算できる" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちはきょうはいいてんきですね",
      duration: 5.0
    )

    assert_equal 3.2, analysis.speech_speed
  end

  test "実際の発話時間を使ってモーラ数から話速を計算できる" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちはきょうはいいてんきですね",
      duration: 10.0,
      speech_duration: 5.0
    )

    assert_equal 3.2, analysis.speech_speed
  end

  test "実際の発話時間が指定されていない場合は録音時間を使う" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちはきょうはいいてんきですね",
      duration: 5.0
    )

    assert_equal 3.2, analysis.speech_speed
  end

  test "録音時間が0の場合は0を返す" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちは",
      duration: 0
    )

    assert_equal 0.0, analysis.speech_speed
  end

  test "実際の発話時間が0の場合は0を返す" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちは",
      duration: 5.0,
      speech_duration: 0
    )

    assert_equal 0.0, analysis.speech_speed
  end

  test "句読点と空白はモーラ数に含めない" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちは、きょうはいいてんきですね。",
      duration: 5.0
    )

    assert_equal 16, analysis.mora_count
  end

  test "促音は1モーラとして数える" do
    analysis = SpeechAnalysis.new(
      transcription: "いっぱい",
      duration: 1.0
    )

    assert_equal 4, analysis.mora_count
  end

  test "長音は1モーラとして数える" do
    analysis = SpeechAnalysis.new(
      transcription: "コーヒー",
      duration: 1.0
    )

    assert_equal 4, analysis.mora_count
  end

  test "文字起こしからフィラー回数を数えられる" do
    analysis = SpeechAnalysis.new(
      transcription: "えー今日はですねあのーおすすめの商品ですえっとこちらになります",
      duration: 5.0
    )

    assert_equal 3, analysis.filler_count
  end

  test "フィラーがない場合は0回を返す" do
    analysis = SpeechAnalysis.new(
      transcription: "今日はおすすめの商品をご紹介します",
      duration: 5.0
    )

    assert_equal 0, analysis.filler_count
  end

  test "1分あたりのフィラー回数を計算できる" do
    analysis = SpeechAnalysis.new(
      transcription: "えー今日はですねあのーおすすめの商品ですえっとこちらになります",
      duration: 60.0
    )

    assert_equal 3.0, analysis.filler_count_per_minute
  end

  test "録音時間が0の場合は1分あたりのフィラー回数を0にする" do
    analysis = SpeechAnalysis.new(
      transcription: "えー今日はおすすめの商品です",
      duration: 0
    )

    assert_equal 0.0, analysis.filler_count_per_minute
  end

  test "1分間のフィラー平均0回は100点" do
    analysis = SpeechAnalysis.new(
      transcription: "",
      duration: 60.0
    )

    assert_equal 100, analysis.filler_score
  end

  test "1分間のフィラー平均1回は80点" do
    analysis = SpeechAnalysis.new(
      transcription: "えー",
      duration: 60.0
    )

    assert_equal 80, analysis.filler_score
  end

  test "1分間のフィラー平均3回は60点" do
    analysis = SpeechAnalysis.new(
      transcription: "えーあのーえっと",
      duration: 60.0
    )

    assert_equal 60, analysis.filler_score
  end

  test "1分間のフィラー平均5回は40点" do
    analysis = SpeechAnalysis.new(
      transcription: "えーあのーえっとまあそのー",
      duration: 60.0
    )

    assert_equal 40, analysis.filler_score
  end

  test "1分間のフィラー平均6回は20点" do
    analysis = SpeechAnalysis.new(
      transcription: "えーあのーえっとまあそのーええ",
      duration: 60.0
    )

    assert_equal 20, analysis.filler_score
  end

  test "録音時間が0の場合はフィラー評価を0点にする" do
    analysis = SpeechAnalysis.new(
      transcription: "えー",
      duration: 0
    )

    assert_equal 0, analysis.filler_score
  end
end
