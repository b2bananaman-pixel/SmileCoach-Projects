require "open3"

class SpeechDurationAnalysis
  SILENCE_THRESHOLD = "-40dB"
  SILENCE_DURATION = "0.1"

  def initialize(audio, duration:)
    @audio = audio
    @duration = duration
  end

  def speech_duration
    return 0.0 unless @audio&.attached?
    return 0.0 if @duration.blank? || @duration <= 0

    silence_duration = detect_silence_duration

    [ @duration - silence_duration, 0.0 ].max
  end

  private

  def detect_silence_duration
    Tempfile.create([ "speech_duration_analysis", ".webm" ]) do |tempfile|
      tempfile.binmode
      tempfile.write(@audio.download)
      tempfile.flush

      _, stderr, = Open3.capture3(
        "ffmpeg",
        "-i", tempfile.path,
        "-af", "silencedetect=noise=#{SILENCE_THRESHOLD}:d=#{SILENCE_DURATION}",
        "-f", "null",
        "-"
      )

      stderr.scan(/silence_duration:\s*([\d.]+)/).sum do |match|
        match[0].to_f
      end
    end
  end
end
