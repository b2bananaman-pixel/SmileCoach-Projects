require "open3"
require "tmpdir"

# AIロープレで発話ごとに録音した利用者のWebM音声を、入力順に1つのWebM（Opus）へ結合する
#
# MediaRecorderで発話ごとに作成したWebMはそれぞれが独立したファイルのため、
# バイト列を単純に連結せず、ffmpegのconcatフィルタでデコードしてから再エンコードする。
#
# 結合した音声はブロックの中でだけ利用でき、ブロックを抜けると一時ディレクトリごと削除する。
#
#   ClerkAudioConcatenator.new(audio_files).call do |result|
#     result.file     # 結合したWebM（読み込み用に開いたFile）
#     result.duration # 結合後の長さ（秒）
#   end
class ClerkAudioConcatenator
  include AnalysisPerformanceMeasurement

  class Error < StandardError; end
  class InvalidInputError < Error; end
  class ConversionError < Error; end

  Result = Struct.new(:file, :duration, keyword_init: true)

  # 10分のAIロープレを想定した上限
  MAX_FILES = 100
  MAX_FILE_SIZE = 10.megabytes
  MAX_TOTAL_SIZE = 30.megabytes
  MAX_DURATION_SECONDS = 11.minutes.to_i

  SAMPLE_RATE = 48_000
  AUDIO_BITRATE = "64k"
  OUTPUT_FILENAME = "clerk_audio.webm".freeze
  STDERR_MAX_LENGTH = 1_000

  def initialize(audio_files)
    @audio_files = Array(audio_files)
  end

  def call
    raise ArgumentError, "block is required" unless block_given?

    validate_inputs!

    total_started_at = monotonic_time

    Dir.mktmpdir("clerk_audio") do |dir|
      input_paths = measure("発話音声コピー") do
        copy_inputs(dir)
      end

      output_path = File.join(dir, OUTPUT_FILENAME)

      measure("発話音声結合") do
        concatenate(input_paths, output_path)
      end

      duration = measure("結合音声の長さ取得") do
        probe_duration(output_path)
      end

      if duration > MAX_DURATION_SECONDS
        raise InvalidInputError,
              "結合した音声が長すぎます（上限#{MAX_DURATION_SECONDS}秒）"
      end

      log_duration(
        "発話音声結合合計（#{input_paths.size}件・#{format('%.2f', duration)}秒）",
        monotonic_time - total_started_at
      )

      File.open(output_path, "rb") do |file|
        yield Result.new(file: file, duration: duration)
      end
    end
  end

  private

  def validate_inputs!
    raise InvalidInputError, "発話音声がありません" if @audio_files.empty?

    if @audio_files.size > MAX_FILES
      raise InvalidInputError,
            "発話音声の数が多すぎます（上限#{MAX_FILES}件）"
    end

    total_size = @audio_files.each_with_index.sum do |audio_file, index|
      size = file_size(audio_file, index)

      raise InvalidInputError, "#{index + 1}件目の発話音声が空です" if size.zero?

      if size > MAX_FILE_SIZE
        raise InvalidInputError,
              "#{index + 1}件目の発話音声が大きすぎます（上限#{MAX_FILE_SIZE}バイト）"
      end

      size
    end

    return if total_size <= MAX_TOTAL_SIZE

    raise InvalidInputError,
          "発話音声の合計サイズが大きすぎます（上限#{MAX_TOTAL_SIZE}バイト）"
  end

  def file_size(audio_file, index)
    if audio_file.respond_to?(:size)
      audio_file.size.to_i
    elsif readable_path(audio_file)
      File.size(readable_path(audio_file))
    else
      raise InvalidInputError, "#{index + 1}件目の発話音声を読み込めません"
    end
  end

  # 利用者が送ったファイル名はコマンドやパスに使わず、連番の安全なファイル名へコピーする
  def copy_inputs(dir)
    @audio_files.each_with_index.map do |audio_file, index|
      input_path = File.join(dir, format("turn_%03d.webm", index))

      if readable_path(audio_file)
        IO.copy_stream(readable_path(audio_file), input_path)
      elsif audio_file.respond_to?(:read)
        audio_file.rewind if audio_file.respond_to?(:rewind)
        IO.copy_stream(audio_file, input_path)
      else
        raise InvalidInputError, "#{index + 1}件目の発話音声を読み込めません"
      end

      input_path
    end
  end

  def readable_path(audio_file)
    return unless audio_file.respond_to?(:path)

    path = audio_file.path
    path if path.present? && File.file?(path)
  end

  # 発話ごとにサンプルレート・チャンネルをそろえてから、入力順に連結する
  def concatenate(input_paths, output_path)
    filters = input_paths.each_index.map do |index|
      "[#{index}:a:0]aresample=#{SAMPLE_RATE}," \
        "aformat=sample_fmts=fltp:channel_layouts=mono[a#{index}]"
    end

    labels = input_paths.each_index.map { |index| "[a#{index}]" }.join

    filter_complex =
      "#{filters.join(';')};#{labels}concat=n=#{input_paths.size}:v=0:a=1[out]"

    # シェルを介さず引数配列で実行し、上限を少し超えた時点で処理を打ち切る
    command = [
      "ffmpeg",
      "-nostdin",
      "-hide_banner",
      "-loglevel", "error",
      "-y",
      *input_paths.flat_map { |input_path| [ "-i", input_path ] },
      "-filter_complex", filter_complex,
      "-map", "[out]",
      "-t", (MAX_DURATION_SECONDS + 1).to_s,
      "-c:a", "libopus",
      "-b:a", AUDIO_BITRATE,
      "-f", "webm",
      output_path
    ]

    _stdout, stderr, status = Open3.capture3(*command)

    unless status.success?
      raise ConversionError,
            "発話音声の結合に失敗しました（exit #{status.exitstatus}）: #{stderr_summary(stderr)}"
    end

    return if File.size?(output_path)

    raise ConversionError, "結合した発話音声が空です"
  end

  def probe_duration(output_path)
    stdout, stderr, status = Open3.capture3(
      "ffprobe",
      "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      output_path
    )

    unless status.success?
      raise ConversionError,
            "結合した発話音声の長さを取得できませんでした: #{stderr_summary(stderr)}"
    end

    duration = Float(stdout.strip, exception: false)

    return duration if duration&.positive?

    raise ConversionError, "結合した発話音声の長さが不正です"
  end

  # ffmpegのエラーは一時ディレクトリ内の連番ファイル名で出力され、利用者のファイル名や発話内容は含まない
  def stderr_summary(stderr)
    stderr.to_s.strip.last(STDERR_MAX_LENGTH)
  end
end
