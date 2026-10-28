require "test_helper"
require "open3"

class ClerkAudioConcatenatorTest < ActiveSupport::TestCase
  FIXTURE_DIR = Rails.root.join("test/fixtures/files")

  # 1秒の声だけの音声と、1秒の声の後に4秒の無音が続く音声
  VOICE_FILE = FIXTURE_DIR.join("test_volume.webm")
  PAUSE_FILE = FIXTURE_DIR.join("speech_duration_long_pause.webm")
  INVALID_FILE = FIXTURE_DIR.join("test_audio.webm")

  FailedStatus = Struct.new(:exitstatus) do
    def success?
      false
    end
  end

  test "WebMを2つ結合して読み込み可能な1つのWebMにできる" do
    concatenate(VOICE_FILE, PAUSE_FILE) do |result|
      assert result.file.size.positive?

      stdout, _stderr, status = Open3.capture3(
        "ffprobe",
        "-v", "error",
        "-show_entries", "stream=codec_name,sample_rate,channels",
        "-of", "default=noprint_wrappers=1",
        result.file.path
      )

      assert status.success?
      assert_includes stdout, "codec_name=opus"
      assert_includes stdout, "sample_rate=48000"
      assert_includes stdout, "channels=1"
    end
  end

  test "結合後の長さが元の音声の合計にほぼ等しい" do
    expected = probe_duration(VOICE_FILE) + probe_duration(PAUSE_FILE)

    concatenate(VOICE_FILE, PAUSE_FILE) do |result|
      assert_in_delta expected, result.duration, 0.15
    end
  end

  test "発話の順序を維持して結合する" do
    voice_duration = probe_duration(VOICE_FILE)
    pause = detect_silences(PAUSE_FILE.to_s).first

    concatenate(VOICE_FILE, PAUSE_FILE) do |result|
      silence = detect_silences(result.file.path).first

      # 1件目の声の後に2件目の声が続き、その後に無音が始まる
      assert_not_nil silence
      assert_in_delta voice_duration + pause[:start], silence[:start], 0.3
    end

    concatenate(PAUSE_FILE, VOICE_FILE) do |result|
      silences = detect_silences(result.file.path)

      # 1件目の無音が先に現れ、無音の後に2件目の声が続く
      assert_equal 1, silences.size
      assert_in_delta pause[:start], silences.first[:start], 0.3
      assert_in_delta pause[:end], silences.first[:end], 0.3
      assert_operator result.duration, :>, silences.first[:end]
    end
  end

  test "1件だけでも結合結果として扱える" do
    concatenate(VOICE_FILE) do |result|
      assert_in_delta probe_duration(VOICE_FILE), result.duration, 0.15
    end
  end

  test "アップロードされた音声ファイルを結合できる" do
    files = [ VOICE_FILE, PAUSE_FILE ].map do |path|
      Rack::Test::UploadedFile.new(path, "audio/webm")
    end

    ClerkAudioConcatenator.new(files).call do |result|
      assert result.duration.positive?
    end
  end

  test "結合した音声を既存のVolumeAnalysisとSpeechDurationAnalysisで分析できる" do
    practice = practices(:one)

    concatenate(VOICE_FILE, PAUSE_FILE) do |result|
      practice.audio.attach(
        io: result.file,
        filename: "clerk_audio.webm",
        content_type: "audio/webm"
      )

      volume = VolumeAnalysis.new(practice.audio).volume

      speech_duration = SpeechDurationAnalysis.new(
        practice.audio,
        duration: result.duration
      ).speech_duration

      pause = detect_silences(PAUSE_FILE.to_s).first

      # 3秒以上の無音は除外され、声のある部分の音量と長さになる
      assert_in_delta(-21.1, volume, 1.5)
      assert_in_delta(
        probe_duration(VOICE_FILE) + pause[:start],
        speech_duration,
        0.5
      )
    end
  end

  test "入力が0件の場合はInvalidInputErrorになる" do
    error = assert_raises(ClerkAudioConcatenator::InvalidInputError) do
      ClerkAudioConcatenator.new([]).call { flunk "ブロックは呼ばれないこと" }
    end

    assert_equal "発話音声がありません", error.message
  end

  test "入力数が上限を超える場合はffmpegを実行せずInvalidInputErrorになる" do
    files = Array.new(ClerkAudioConcatenator::MAX_FILES + 1) do
      StringIO.new("a")
    end

    Open3.stub(:capture3, ->(*_args) { flunk "ffmpegを実行しないこと" }) do
      assert_raises(ClerkAudioConcatenator::InvalidInputError) do
        ClerkAudioConcatenator.new(files).call { flunk "ブロックは呼ばれないこと" }
      end
    end
  end

  test "空の発話音声が含まれる場合はInvalidInputErrorになる" do
    files = [ File.open(VOICE_FILE, "rb"), StringIO.new("") ]

    error = assert_raises(ClerkAudioConcatenator::InvalidInputError) do
      ClerkAudioConcatenator.new(files).call { flunk "ブロックは呼ばれないこと" }
    end

    assert_equal "2件目の発話音声が空です", error.message
  ensure
    files&.first&.close
  end

  test "1件あたりのサイズが上限を超える場合はInvalidInputErrorになる" do
    oversized = StringIO.new("a")

    def oversized.size
      ClerkAudioConcatenator::MAX_FILE_SIZE + 1
    end

    assert_raises(ClerkAudioConcatenator::InvalidInputError) do
      ClerkAudioConcatenator.new([ oversized ]).call { flunk "ブロックは呼ばれないこと" }
    end
  end

  test "合計サイズが上限を超える場合はInvalidInputErrorになる" do
    files = Array.new(4) do
      file = StringIO.new("a")

      def file.size
        ClerkAudioConcatenator::MAX_FILE_SIZE
      end

      file
    end

    error = assert_raises(ClerkAudioConcatenator::InvalidInputError) do
      ClerkAudioConcatenator.new(files).call { flunk "ブロックは呼ばれないこと" }
    end

    assert_includes error.message, "合計サイズ"
  end

  test "結合後の長さが上限を超える場合はInvalidInputErrorになる" do
    error = nil

    with_stubbed_const(:MAX_DURATION_SECONDS, 1) do
      error = assert_raises(ClerkAudioConcatenator::InvalidInputError) do
        concatenate(VOICE_FILE, PAUSE_FILE) { flunk "ブロックは呼ばれないこと" }
      end
    end

    assert_includes error.message, "長すぎます"
  end

  test "不正な音声ファイルが含まれる場合はConversionErrorになり何件目か分かる" do
    error = assert_raises(ClerkAudioConcatenator::ConversionError) do
      concatenate(VOICE_FILE, INVALID_FILE) { flunk "ブロックは呼ばれないこと" }
    end

    assert_includes error.message, "発話音声の結合に失敗しました"
    assert_includes error.message, "turn_001.webm"
  end

  test "ffmpegが失敗した場合は終了コードとエラー内容を含むConversionErrorになる" do
    Open3.stub(
      :capture3,
      ->(*_args) { [ "", "ffmpeg test failure", FailedStatus.new(1) ] }
    ) do
      error = assert_raises(ClerkAudioConcatenator::ConversionError) do
        concatenate(VOICE_FILE) { flunk "ブロックは呼ばれないこと" }
      end

      assert_includes error.message, "exit 1"
      assert_includes error.message, "ffmpeg test failure"
    end
  end

  test "ffmpegの実行時に利用者のファイル名をコマンドに含めない" do
    upload = Rack::Test::UploadedFile.new(
      VOICE_FILE,
      "audio/webm",
      original_filename: "$(rm -rf ~); turn.webm"
    )

    commands = []
    original_capture3 = Open3.method(:capture3)

    Open3.stub(
      :capture3,
      ->(*args) { commands << args; original_capture3.call(*args) }
    ) do
      ClerkAudioConcatenator.new([ upload ]).call { |result| assert result.duration.positive? }
    end

    ffmpeg_command = commands.find { |args| args.first == "ffmpeg" }

    assert_not_nil ffmpeg_command
    refute(ffmpeg_command.any? { |arg| arg.include?("rm -rf") })
    assert(ffmpeg_command.any? { |arg| arg.end_with?("/turn_000.webm") })
  end

  test "成功時は一時ディレクトリを削除する" do
    directories = track_temporary_directories do
      concatenate(VOICE_FILE, PAUSE_FILE) do |result|
        assert File.exist?(result.file.path)
      end
    end

    assert_equal 1, directories.size
    assert_not Dir.exist?(directories.first)
  end

  test "ffmpegが失敗した場合も一時ディレクトリを削除する" do
    directories = track_temporary_directories do
      assert_raises(ClerkAudioConcatenator::ConversionError) do
        concatenate(VOICE_FILE, INVALID_FILE) { flunk "ブロックは呼ばれないこと" }
      end
    end

    assert_equal 1, directories.size
    assert_not Dir.exist?(directories.first)
  end

  test "ブロック内で例外が発生した場合も一時ディレクトリを削除する" do
    directories = track_temporary_directories do
      assert_raises(RuntimeError) do
        concatenate(VOICE_FILE) { raise "呼び出し側の処理に失敗" }
      end
    end

    assert_equal 1, directories.size
    assert_not Dir.exist?(directories.first)
  end

  test "ブロックなしで呼び出した場合はArgumentErrorになる" do
    assert_raises(ArgumentError) do
      ClerkAudioConcatenator.new([ File.open(VOICE_FILE, "rb") ]).call
    end
  end

  test "結合の処理時間をログに出す" do
    logged_messages = []

    Rails.logger.stub(:info, ->(message = nil) { logged_messages << message.to_s }) do
      concatenate(VOICE_FILE, PAUSE_FILE) { |_result| nil }
    end

    [
      "[AnalysisPerformance] 発話音声コピー: ",
      "[AnalysisPerformance] 発話音声結合: ",
      "[AnalysisPerformance] 結合音声の長さ取得: ",
      "[AnalysisPerformance] 発話音声結合合計（2件・"
    ].each do |prefix|
      assert(
        logged_messages.any? { |message| message.start_with?(prefix) },
        "#{prefix}がログに出力されていません"
      )
    end
  end

  private

  def concatenate(*paths, &block)
    files = paths.map { |path| File.open(path, "rb") }

    ClerkAudioConcatenator.new(files).call(&block)
  ensure
    files&.each(&:close)
  end

  def probe_duration(path)
    stdout, = Open3.capture3(
      "ffprobe",
      "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      path.to_s
    )

    Float(stdout.strip)
  end

  def detect_silences(path)
    _stdout, stderr, = Open3.capture3(
      "ffmpeg",
      "-nostdin",
      "-i", path,
      "-af", "silencedetect=noise=-40dB:d=0.5",
      "-f", "null",
      "-"
    )

    starts = stderr.scan(/silence_start:\s*(-?[\d.]+)/).flatten.map(&:to_f)
    ends = stderr.scan(/silence_end:\s*([\d.]+)/).flatten.map(&:to_f)

    starts.zip(ends).map { |start_time, end_time| { start: start_time, end: end_time } }
  end

  def track_temporary_directories
    directories = []
    original_mktmpdir = Dir.method(:mktmpdir)

    Dir.stub(
      :mktmpdir,
      lambda do |*args, &block|
        original_mktmpdir.call(*args) do |dir|
          directories << dir
          block.call(dir)
        end
      end
    ) do
      yield
    end

    directories
  end

  def with_stubbed_const(name, value)
    original = ClerkAudioConcatenator.const_get(name)

    ClerkAudioConcatenator.send(:remove_const, name)
    ClerkAudioConcatenator.const_set(name, value)

    yield
  ensure
    ClerkAudioConcatenator.send(:remove_const, name)
    ClerkAudioConcatenator.const_set(name, original)
  end
end
