require "test_helper"
require "open3"

class AiRoleplayVoiceAnalysisServiceTest < ActiveSupport::TestCase
  FIXTURE_DIR = Rails.root.join("test/fixtures/files")
  VOICE_FILE = FIXTURE_DIR.join("test_volume.webm")
  PAUSE_FILE = FIXTURE_DIR.join("speech_duration_long_pause.webm")
  INVALID_FILE = FIXTURE_DIR.join("test_audio.webm")

  CLERK_MESSAGES = [
    "いらっしゃいませ。本日はどのようなご用件でしょうか。",
    "えーと、ご家族は何名でご利用ですか。"
  ].freeze

  CUSTOMER_MESSAGES = [
    "スマホの乗り換えを考えています。",
    "4人家族です。"
  ].freeze

  FailedStatus = Struct.new(:exitstatus) do
    def success?
      false
    end
  end

  setup do
    @user = users(:one)
    @practice_theme = practice_themes(:one)

    @session = AiRoleplaySession.create!(
      user: @user,
      practice_theme: @practice_theme,
      duration: 60.0,
      end_reason: "user_end"
    )

    CLERK_MESSAGES.zip(CUSTOMER_MESSAGES).each do |clerk_message, customer_message|
      @session.ai_roleplay_messages.create!(role: "user", content: clerk_message)
      @session.ai_roleplay_messages.create!(role: "assistant", content: customer_message)
    end

    @opened_files = []
  end

  teardown do
    @opened_files.each(&:close)
  end

  test "利用者の発話音声からPracticeとAnalysisを作成してセッションに関連付ける" do
    practice = nil

    assert_difference([ "Practice.count", "Analysis.count" ], 1) do
      practice = with_stubbed_ai_comment do
        analyze(VOICE_FILE, PAUSE_FILE)
      end
    end

    assert practice.persisted?
    assert_equal @session, practice.ai_roleplay_session
    assert_equal practice, @session.reload.practice
    assert_equal @session.user, practice.user
    assert_equal @session.practice_theme, practice.practice_theme

    assert practice.audio.attached?
    assert_equal "ai_roleplay_clerk_audio.webm", practice.audio.filename.to_s
    assert_equal "audio/webm", practice.audio.content_type

    expected_duration = probe_duration(VOICE_FILE) + probe_duration(PAUSE_FILE)
    assert_in_delta expected_duration, practice.duration, 0.15

    analysis = practice.analysis
    assert analysis.persisted?
    assert_not_nil analysis.speech_speed
    assert_not_nil analysis.speech_speed_score
    assert_equal 1, analysis.filler_count
    assert_not_nil analysis.filler_score
    assert_in_delta(-21.1, analysis.volume, 1.5)
    assert_not_nil analysis.volume_score
    assert_nil analysis.smile_score
    assert_equal "テスト用のAIコメントです。", analysis.ai_comment
  end

  test "文字起こしには利用者の発言だけを会話の順番で保存しAI顧客の発言を含めない" do
    practice = with_stubbed_ai_comment do
      analyze(VOICE_FILE, PAUSE_FILE)
    end

    assert_equal CLERK_MESSAGES.join("\n"), practice.transcription

    CUSTOMER_MESSAGES.each do |customer_message|
      refute_includes practice.transcription, customer_message
    end
  end

  test "Groqの文字起こしAPIを追加で呼び出さない" do
    transcription_service = Object.new

    def transcription_service.call
      raise "文字起こしは呼び出さないこと"
    end

    practice = nil

    GroqTranscriptionService.stub(:new, ->(_audio) { transcription_service }) do
      GuestTranscriptionService.stub(:new, ->(_audio) { transcription_service }) do
        practice = with_stubbed_ai_comment do
          analyze(VOICE_FILE, PAUSE_FILE)
        end
      end
    end

    assert practice.analysis.persisted?
  end

  test "利用者の発言がない場合は音声を結合せず分析しない" do
    session = AiRoleplaySession.create!(
      user: @user,
      practice_theme: @practice_theme
    )

    Open3.stub(:capture3, ->(*_args) { flunk "ffmpegを実行しないこと" }) do
      assert_no_difference([ "Practice.count", "Analysis.count" ]) do
        result = AiRoleplayVoiceAnalysisService.new(
          ai_roleplay_session: session,
          audio_files: []
        ).call

        assert_nil result
      end
    end
  end

  test "発話音声がない場合は分析しない" do
    Open3.stub(:capture3, ->(*_args) { flunk "ffmpegを実行しないこと" }) do
      assert_no_difference([ "Practice.count", "Analysis.count" ]) do
        assert_nil analyze
      end
    end
  end

  test "利用者の発言数と発話音声数が一致しない場合は分析しない" do
    logged_messages = []

    Open3.stub(:capture3, ->(*_args) { flunk "ffmpegを実行しないこと" }) do
      Rails.logger.stub(:info, ->(message = nil) { logged_messages << message.to_s }) do
        assert_no_difference([ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count" ]) do
          assert_nil analyze(VOICE_FILE)
          assert_nil analyze(VOICE_FILE, PAUSE_FILE, VOICE_FILE)
        end
      end
    end

    assert(
      logged_messages.any? { |message| message.include?("発言数（2件）と発話音声数（1件）が一致しません") }
    )
  end

  test "不正な音声が含まれる場合はPracticeとAnalysisと音声を残さず例外を送出する" do
    assert_no_difference([ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count" ]) do
      assert_raises(ClerkAudioConcatenator::ConversionError) do
        with_stubbed_ai_comment do
          analyze(VOICE_FILE, INVALID_FILE)
        end
      end
    end

    assert_nil @session.reload.practice
  end

  test "音声結合に失敗した場合はPracticeとAnalysisと音声を残さず例外を送出する" do
    Open3.stub(:capture3, ->(*_args) { [ "", "ffmpeg test failure", FailedStatus.new(1) ] }) do
      assert_no_difference([ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count" ]) do
        assert_raises(ClerkAudioConcatenator::ConversionError) do
          analyze(VOICE_FILE, PAUSE_FILE)
        end
      end
    end
  end

  test "音声分析に失敗した場合は保存済みのPracticeと音声を削除して例外を送出する" do
    analysis_service = Object.new

    def analysis_service.call
      raise "分析に失敗"
    end

    PracticeAnalysisService.stub(:new, ->(_practice) { analysis_service }) do
      assert_no_difference(
        [ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]
      ) do
        error = assert_raises(RuntimeError) do
          analyze(VOICE_FILE, PAUSE_FILE)
        end

        assert_equal "分析に失敗", error.message
      end
    end

    assert_nil @session.reload.practice
  end

  test "Analysisの保存途中で失敗した場合も途中の結果を残さない" do
    PracticeAnalysisService.stub(
      :new,
      lambda do |practice|
        Struct.new(:practice) do
          def call
            practice.create_analysis!(total_score: 1)
            raise ActiveRecord::RecordInvalid, practice
          end
        end.new(practice)
      end
    ) do
      assert_no_difference([ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count" ]) do
        assert_raises(ActiveRecord::RecordInvalid) do
          analyze(VOICE_FILE, PAUSE_FILE)
        end
      end
    end
  end

  test "AIコメント生成に失敗しても話し方の分析結果を保存する" do
    ai_comment_service = Object.new

    def ai_comment_service.call
      raise "Groq API request failed"
    end

    practice = nil

    AiCommentService.stub(:new, ->(_analysis) { ai_comment_service }) do
      practice = analyze(VOICE_FILE, PAUSE_FILE)
    end

    assert practice.persisted?
    assert practice.analysis.persisted?
    assert_nil practice.analysis.ai_comment
  end

  test "同じセッションで重複実行してもPracticeは1件だけ作成される" do
    first = nil

    assert_difference([ "Practice.count", "Analysis.count" ], 1) do
      with_stubbed_ai_comment do
        first = analyze(VOICE_FILE, PAUSE_FILE)

        Open3.stub(:capture3, ->(*_args) { flunk "2回目はffmpegを実行しないこと" }) do
          assert_nil analyze(VOICE_FILE, PAUSE_FILE)
        end
      end
    end

    assert_equal first, @session.reload.practice
  end

  test "同時実行で先に保存された場合は重複エラーにせずスキップする" do
    Practice.create!(
      user: @user,
      practice_theme: @practice_theme,
      ai_roleplay_session: @session
    )

    service = AiRoleplayVoiceAnalysisService.new(
      ai_roleplay_session: @session,
      audio_files: open_files(VOICE_FILE, PAUSE_FILE)
    )

    # 事前確認の時点では未作成で、保存時に他の処理が先に作成していた状況を再現する
    checks = 0

    service.stub(:already_analyzed?, -> { (checks += 1) > 1 }) do
      assert_no_difference([ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count" ]) do
        assert_nil service.call
      end
    end
  end

  test "成功時も失敗時も一時ディレクトリを削除する" do
    directories = track_temporary_directories do
      with_stubbed_ai_comment do
        analyze(VOICE_FILE, PAUSE_FILE)
      end

      session = AiRoleplaySession.create!(user: @user, practice_theme: @practice_theme)
      session.ai_roleplay_messages.create!(role: "user", content: "いらっしゃいませ")

      assert_raises(ClerkAudioConcatenator::ConversionError) do
        AiRoleplayVoiceAnalysisService.new(
          ai_roleplay_session: session,
          audio_files: open_files(INVALID_FILE)
        ).call
      end
    end

    assert_equal 2, directories.size
    directories.each { |directory| assert_not Dir.exist?(directory) }
  end

  test "処理時間をAnalysisPerformance形式でログに出す" do
    logged_messages = []

    Rails.logger.stub(:info, ->(message = nil) { logged_messages << message.to_s }) do
      with_stubbed_ai_comment do
        analyze(VOICE_FILE, PAUSE_FILE)
      end
    end

    [
      "[AnalysisPerformance] 発話音声結合合計（2件・",
      "[AnalysisPerformance] 音声分析用Practice保存: ",
      "[AnalysisPerformance] 声量分析: ",
      "[AnalysisPerformance] AIロープレ音声分析合計: "
    ].each do |prefix|
      assert(
        logged_messages.any? { |message| message.start_with?(prefix) },
        "#{prefix}がログに出力されていません"
      )
    end
  end

  test "通常録画のPracticeとAnalysisには影響しない" do
    normal_practice = practices(:one)
    normal_analysis = analyses(:one)

    assert_no_difference("Practice.where(ai_roleplay_session_id: nil).count") do
      with_stubbed_ai_comment do
        analyze(VOICE_FILE, PAUSE_FILE)
      end
    end

    assert_nil normal_practice.reload.ai_roleplay_session_id
    assert_equal normal_analysis.attributes, normal_analysis.reload.attributes
  end

  private

  def analyze(*paths)
    AiRoleplayVoiceAnalysisService.new(
      ai_roleplay_session: @session,
      audio_files: open_files(*paths)
    ).call
  end

  def open_files(*paths)
    files = paths.map { |path| File.open(path, "rb") }
    @opened_files.concat(files)
    files
  end

  def with_stubbed_ai_comment(&block)
    AiCommentService.stub(
      :new,
      ->(_analysis) { Struct.new(:call).new("テスト用のAIコメントです。") },
      &block
    )
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
end
