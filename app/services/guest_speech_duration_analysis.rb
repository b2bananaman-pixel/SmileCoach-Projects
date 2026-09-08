require "open3"

class GuestSpeechDurationAnalysis
  SILENCE_THRESHOLD = "-40dB"
  SILENCE_DURATION = "3.0"

  def initialize(audio_file, duration:)
    @audio_file = audio_file
    @duration = duration
  end

  def speech_duration
    return 0.0 unless @audio_file
    return 0.0 if @duration.blank? || @duration <= 0

    silence_duration = detect_silence_duration

    [ @duration - silence_duration, 0.0 ].max
  end

  private

  def detect_silence_duration
    _, stderr, = Open3.capture3(
      "ffmpeg",
      "-i", @audio_file.path,
      "-af", "silencedetect=noise=#{SILENCE_THRESHOLD}:d=#{SILENCE_DURATION}",
      "-f", "null",
      "-"
    )

    stderr.scan(/silence_duration:\s*([\d.]+)/).sum do |match|
      match[0].to_f
    end
  end
end
