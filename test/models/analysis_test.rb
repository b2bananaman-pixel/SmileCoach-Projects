require "test_helper"

class AnalysisTest < ActiveSupport::TestCase
  test "分析結果を保存できる" do
    practice = practices(:one)

    analysis = Analysis.create!(
      practice: practice,
      total_score: 85,
      smile_score: 90,
      voice_brightness: 72.5,
      voice_brightness_score: 80,
      voice_clarity: 68.5,
      voice_clarity_score: 75,
      speech_speed: 5.2,
      speech_speed_score: 85,
      filler_count: 3,
      filler_score: 90,
      volume: -21.1,
      volume_score: 80,
      ai_comment: "明るく話せています。もう少しゆっくり話すとさらに良くなります。"
    )

    assert analysis.persisted?
    assert_equal practice, analysis.practice
    assert_equal 85, analysis.total_score
    assert_equal 90, analysis.smile_score
    assert_in_delta 72.5, analysis.voice_brightness, 0.01
    assert_equal 80, analysis.voice_brightness_score
    assert_in_delta 68.5, analysis.voice_clarity, 0.01
    assert_equal 75, analysis.voice_clarity_score
    assert_in_delta 5.2, analysis.speech_speed, 0.01
    assert_equal 85, analysis.speech_speed_score
    assert_equal 3, analysis.filler_count
    assert_equal 90, analysis.filler_score
    assert_in_delta(-21.1, analysis.volume, 0.01)
    assert_equal 80, analysis.volume_score
    assert_equal "明るく話せています。もう少しゆっくり話すとさらに良くなります。", analysis.ai_comment
  end

  test "practiceからanalysisを取得できる" do
    practice = practices(:one)

    analysis = Analysis.create!(
      practice: practice,
      total_score: 85
    )

    assert_equal analysis, practice.analysis
  end
end
