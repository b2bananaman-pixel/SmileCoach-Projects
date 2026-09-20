require "open3"
require "tempfile"

class VideoAudioExtractor
  def initialize(video_file)
    @video_file = video_file
  end

  def call
    input_file = create_input_file
    output_file = Tempfile.new([ "practice_audio", ".webm" ])

    command = [
      "ffmpeg",
      "-y",
      "-i", input_file.path,
      "-vn",
      "-acodec", "copy",
      output_file.path
    ]

    _stdout, stderr, status = Open3.capture3(*command)

    unless status.success?
      raise "動画から音声を抽出できませんでした: #{stderr}"
    end

    output_file.rewind
    output_file
  ensure
    input_file&.close!
  end

  private

  def create_input_file
    input_file = Tempfile.new([ "practice_video", ".webm" ])

    @video_file.rewind
    input_file.binmode
    input_file.write(@video_file.read)
    input_file.flush
    input_file.rewind

    input_file
  end
end
