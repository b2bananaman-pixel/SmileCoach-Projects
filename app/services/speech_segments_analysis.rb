require "open3"

class SpeechSegmentsAnalysis
  SILENCE_THRESHOLD = "-40dB"
  SILENCE_DURATION = "0.5"

  def initialize(audio, duration:)
    @audio = audio
    @duration = duration
  end

  def speech_segments
    return [] unless @audio&.attached?
    return [] if @duration.blank? || @duration <= 0

    silence_segments = detect_silence_segments
    build_speech_segments(silence_segments)
  end

  private

  def detect_silence_segments
    Tempfile.create([ "speech_segments_analysis", ".webm" ]) do |tempfile|
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

      parse_silence_segments(stderr)
    end
  end

  def parse_silence_segments(stderr)
    starts = stderr.scan(/silence_start:\s*([\d.]+)/).flatten.map(&:to_f)
    ends = stderr.scan(/silence_end:\s*([\d.]+)/).flatten.map(&:to_f)

    starts.zip(ends).map do |start_time, end_time|
      next unless start_time && end_time

      {
        start: start_time,
        end: end_time
      }
    end.compact
  end

  def build_speech_segments(silence_segments)
    segments = []
    current_time = 0.0

    silence_segments.each do |silence|
      if silence[:start] > current_time
        segments << {
          start: current_time,
          end: silence[:start]
        }
      end

      current_time = silence[:end]
    end

    if current_time < @duration
      segments << {
        start: current_time,
        end: @duration
      }
    end

    segments
  end
end
