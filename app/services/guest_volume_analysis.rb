require "open3"

class GuestVolumeAnalysis
  SILENCE_THRESHOLD = "-40dB"
  SILENCE_DURATION = "0.1"

  def initialize(audio_file)
    @audio_file = audio_file
  end

  def volume
    return 0.0 unless @audio_file

    _, stderr, = Open3.capture3(
      "ffmpeg",
      "-i", @audio_file.path,
      "-af", "silenceremove=stop_periods=-1:stop_duration=#{SILENCE_DURATION}:stop_threshold=#{SILENCE_THRESHOLD},volumedetect",
      "-f", "null",
      "-"
    )

    volume_line = stderr.lines.find { |line| line.include?("mean_volume:") }

    return 0.0 unless volume_line

    volume_line.match(/mean_volume:\s*(-?\d+(?:\.\d+)?) dB/)[1].to_f
  end
end
