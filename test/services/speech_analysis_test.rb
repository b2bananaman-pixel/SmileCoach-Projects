require "test_helper"

class SpeechAnalysisTest < ActiveSupport::TestCase
  test "文字数と録音時間から話速を計算できる" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちはきょうはいいてんきですね",
      duration: 5.0
    )

    assert_equal 3.4, analysis.speech_speed
  end

  test "実際の発話時間を使って話速を計算できる" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちはきょうはいいてんきですね",
      duration: 10.0,
      speech_duration: 5.0
    )

    assert_equal 3.4, analysis.speech_speed
  end

  test "実際の発話時間が指定されていない場合は録音時間を使う" do
    analysis = SpeechAnalysis.new(
      transcription: "こんにちはきょうはいいてんきですね",
      duration: 5.0
    )

    assert_equal 3.4, analysis.speech_speed
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
