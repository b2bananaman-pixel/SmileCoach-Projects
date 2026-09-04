require "test_helper"

class VolumeAnalysisTest < ActiveSupport::TestCase
  test "音声データから声量を取得できる" do
    practice = practices(:one)

    fixture_path = Rails.root.join("test/fixtures/files/test_volume.webm")

    File.open(fixture_path) do |file|
      practice.audio.attach(
        io: file,
        filename: "test_volume.webm",
        content_type: "audio/webm"
      )
    end

    volume_analysis = VolumeAnalysis.new(practice.audio)

    assert_in_delta -21.1, volume_analysis.volume, 0.5
  end

  test "無音を除いた発話部分の平均音量を取得できる" do
    practice = practices(:one)

    fixture_path = Rails.root.join("test/fixtures/files/volume_test_silence.webm")

    File.open(fixture_path) do |file|
      practice.audio.attach(
        io: file,
        filename: "volume_test_silence.webm",
        content_type: "audio/webm"
      )
    end

    volume_analysis = VolumeAnalysis.new(practice.audio)

    assert_in_delta -21.2, volume_analysis.volume, 0.5
  end

  test "音声データがない場合は0を返す" do
    volume_analysis = VolumeAnalysis.new(nil)

    assert_equal 0.0, volume_analysis.volume
  end
end
