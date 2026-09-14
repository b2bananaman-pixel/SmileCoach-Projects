require "test_helper"

class SpeechSegmentsAnalysisTest < ActiveSupport::TestCase
  test "silence segments are excluded from speech segments" do
    analysis = SpeechSegmentsAnalysis.new(
      nil,
      duration: 10.0
    )

    silence_segments = [
      { start: 3.0, end: 4.0 },
      { start: 7.0, end: 8.5 }
    ]

    speech_segments = analysis.send(
      :build_speech_segments,
      silence_segments
    )

    assert_equal(
      [
        { start: 0.0, end: 3.0 },
        { start: 4.0, end: 7.0 },
        { start: 8.5, end: 10.0 }
      ],
      speech_segments
    )
  end

  test "returns empty array when audio is not attached" do
    analysis = SpeechSegmentsAnalysis.new(
      nil,
      duration: 10.0
    )

    assert_equal [], analysis.speech_segments
  end

  test "returns empty array when duration is invalid" do
    analysis = SpeechSegmentsAnalysis.new(
      nil,
      duration: 0
    )

    assert_equal [], analysis.speech_segments
  end
end
