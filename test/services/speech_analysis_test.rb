require "test_helper"

class SpeechAnalysisTest < ActiveSupport::TestCase
  test "文字数と録音時間から話速を計算できる" do
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
end
