require "open3"

class VolumeAnalysis
  SILENCE_THRESHOLD = "-40dB"
  SILENCE_DURATION = "0.1"

  def initialize(audio)
    @audio = audio
  end

  def volume
    return 0.0 unless @audio&.attached?

    Tempfile.create([ "volume_analysis", ".webm" ]) do |tempfile|
      tempfile.binmode
      tempfile.write(@audio.download)
      tempfile.flush

      _, stderr, = Open3.capture3(
        "ffmpeg",
        "-i", tempfile.path,
        "-af", "silenceremove=stop_periods=-1:stop_duration=#{SILENCE_DURATION}:stop_threshold=#{SILENCE_THRESHOLD},volumedetect",
        "-f", "null",
        "-"
      )

      volume_line = stderr.lines.find { |line| line.include?("mean_volume:") }

      return 0.0 unless volume_line

      volume_line.match(/mean_volume:\s*(-?\d+(?:\.\d+)?) dB/)[1].to_f
    end
  end
end
