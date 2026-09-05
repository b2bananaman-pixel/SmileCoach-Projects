require "test_helper"

class ScoreAnalysisTest < ActiveSupport::TestCase
  test "話速5.0モーラ/秒は100点" do
    analysis = ScoreAnalysis.new(speech_speed: 5.0, volume: -17.0)

    assert_equal 100, analysis.speech_speed_score
  end

  test "話速5.5モーラ/秒は100点" do
    analysis = ScoreAnalysis.new(speech_speed: 5.5, volume: -17.0)

    assert_equal 100, analysis.speech_speed_score
  end

  test "話速6.0モーラ/秒は100点" do
    analysis = ScoreAnalysis.new(speech_speed: 6.0, volume: -17.0)

    assert_equal 100, analysis.speech_speed_score
  end

  test "話速4.9モーラ/秒は80点" do
    analysis = ScoreAnalysis.new(speech_speed: 4.9, volume: -17.0)

    assert_equal 80, analysis.speech_speed_score
  end

  test "話速6.1モーラ/秒は80点" do
    analysis = ScoreAnalysis.new(speech_speed: 6.1, volume: -17.0)

    assert_equal 80, analysis.speech_speed_score
  end

  test "話速3.9モーラ/秒は60点" do
    analysis = ScoreAnalysis.new(speech_speed: 3.9, volume: -17.0)

    assert_equal 60, analysis.speech_speed_score
  end

  test "話速7.1モーラ/秒は60点" do
    analysis = ScoreAnalysis.new(speech_speed: 7.1, volume: -17.0)

    assert_equal 60, analysis.speech_speed_score
  end

  test "話速2.9モーラ/秒は40点" do
    analysis = ScoreAnalysis.new(speech_speed: 2.9, volume: -17.0)

    assert_equal 40, analysis.speech_speed_score
  end

  test "話速8.1モーラ/秒は40点" do
    analysis = ScoreAnalysis.new(speech_speed: 8.1, volume: -17.0)

    assert_equal 40, analysis.speech_speed_score
  end

  test "話速1.9モーラ/秒は20点" do
    analysis = ScoreAnalysis.new(speech_speed: 1.9, volume: -17.0)

    assert_equal 20, analysis.speech_speed_score
  end

  test "話速9.0モーラ/秒は20点" do
    analysis = ScoreAnalysis.new(speech_speed: 9.0, volume: -17.0)

    assert_equal 20, analysis.speech_speed_score
  end

  test "話速0モーラ/秒は0点" do
    analysis = ScoreAnalysis.new(speech_speed: 0, volume: -17.0)

    assert_equal 0, analysis.speech_speed_score
  end

  test "声量-17.0dBは100点" do
    analysis = ScoreAnalysis.new(speech_speed: 5.5, volume: -17.0)

    assert_equal 100, analysis.volume_score
  end

  test "声量-22.0dBは80点" do
    analysis = ScoreAnalysis.new(speech_speed: 5.5, volume: -22.0)

    assert_equal 80, analysis.volume_score
  end

  test "声量-27.0dBは60点" do
    analysis = ScoreAnalysis.new(speech_speed: 5.5, volume: -27.0)

    assert_equal 60, analysis.volume_score
  end

  test "声量-32.0dBは40点" do
    analysis = ScoreAnalysis.new(speech_speed: 5.5, volume: -32.0)

    assert_equal 40, analysis.volume_score
  end

  test "声量-40.0dBは20点" do
    analysis = ScoreAnalysis.new(speech_speed: 5.5, volume: -40.0)

    assert_equal 20, analysis.volume_score
  end

  test "総合点は話速・フィラー・声量の平均になる" do
    analysis = ScoreAnalysis.new(
      speech_speed: 5.5,
      volume: -22.0,
      filler_score: 100
    )

    assert_equal 93, analysis.total_score
  end

  test "話速が分析できない場合は0点になる" do
    analysis = ScoreAnalysis.new(
      speech_speed: 0,
      volume: -22.0
    )

    assert_equal 0, analysis.speech_speed_score
  end

  test "声量が分析できない場合は0点になる" do
    analysis = ScoreAnalysis.new(
      speech_speed: 5.5,
      volume: 0
    )

    assert_equal 0, analysis.volume_score
  end
end
