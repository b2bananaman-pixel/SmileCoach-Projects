require "test_helper"

class SpeechDurationAnalysisTest < ActiveSupport::TestCase
  test "無音時間を除いた実際の発話時間を計算できる" do
    practice = practices(:one)

    fixture_path = Rails.root.join("test/fixtures/files/volume_test_silence.webm")

    File.open(fixture_path) do |file|
      practice.audio.attach(
        io: file,
        filename: "volume_test_silence.webm",
        content_type: "audio/webm"
      )
    end

    analysis = SpeechDurationAnalysis.new(
      practice.audio,
      duration: 2.0
    )

    assert_in_delta 1.0, analysis.speech_duration, 0.1
  end

  test "音声データがない場合は0を返す" do
    analysis = SpeechDurationAnalysis.new(
      nil,
      duration: 5.0
    )

    assert_equal 0.0, analysis.speech_duration
  end

  test "録音時間が0の場合は0を返す" do
    practice = practices(:one)

    fixture_path = Rails.root.join("test/fixtures/files/volume_test_silence.webm")

    File.open(fixture_path) do |file|
      practice.audio.attach(
        io: file,
        filename: "volume_test_silence.webm",
        content_type: "audio/webm"
      )
    end

    analysis = SpeechDurationAnalysis.new(
      practice.audio,
      duration: 0
    )

    assert_equal 0.0, analysis.speech_duration
  end
end
