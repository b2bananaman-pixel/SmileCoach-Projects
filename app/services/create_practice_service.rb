class CreatePracticeService
  def initialize(user:, practice_theme:, audio:, duration:, video: nil)
    @user = user
    @practice_theme = practice_theme
    @audio = audio
    @duration = duration
    @video = video
  end

  def call
    total_started_at = monotonic_time

    practice = measure("録画データ保存") do
      create_practice
    end

    transcription = measure("Groq文字起こし") do
      transcribe(practice)
    end

    measure("文字起こし保存") do
      practice.update!(transcription: transcription)
    end

    volume = measure("声量分析") do
      VolumeAnalysis.new(practice.audio).volume
    end

    speech_duration = measure("発話時間分析") do
      SpeechDurationAnalysis.new(
        practice.audio,
        duration: practice.duration
      ).speech_duration
    end

    speech_speed = nil
    filler_count = nil
    filler_score = nil

    measure("話速・フィラー分析") do
      speech_analysis = SpeechAnalysis.new(
        transcription: practice.transcription,
        duration: practice.duration,
        speech_duration: speech_duration
      )

      speech_speed = speech_analysis.speech_speed
      filler_count = speech_analysis.filler_count
      filler_score = speech_analysis.filler_score
    end

    score_analysis = measure("スコア計算") do
      ScoreAnalysis.new(
        speech_speed: speech_speed,
        volume: volume,
        filler_score: filler_score
      )
    end

    analysis = measure("Analysis保存") do
      practice.create_analysis!(
        volume: volume,
        volume_score: score_analysis.volume_score,
        speech_speed: speech_speed,
        speech_speed_score: score_analysis.speech_speed_score,
        filler_count: filler_count,
        total_score: score_analysis.total_score,
        filler_score: filler_score
      )
    end

    begin
      ai_comment = measure("AIコメント生成") do
        AiCommentService.new(analysis).call
      end

      measure("AIコメント保存") do
        analysis.update!(ai_comment: ai_comment)
      end
    rescue StandardError => e
      Rails.logger.error(
        "AIコメント生成に失敗しました: #{e.class}"
      )
    end

    log_duration(
      "サーバー分析合計",
      monotonic_time - total_started_at
    )

    practice
  end

  private

  def create_practice
    practice = Practice.new(
      user: @user,
      practice_theme: @practice_theme,
      duration: @duration
    )

    extracted_audio = nil

    if @audio.present?
      practice.audio.attach(@audio)
    elsif @video.present?
      extracted_audio = measure("動画→音声抽出") do
        VideoAudioExtractor.new(@video.tempfile).call
      end

      practice.audio.attach(
        io: extracted_audio,
        filename: "practice_audio.webm",
        content_type: "audio/webm"
      )
    end

    practice.video.attach(@video) if @video.present?
    practice.save!

    practice
  ensure
    extracted_audio&.close!
  end

  def transcribe(practice)
    result = GroqTranscriptionService.new(practice.audio).call
    result["text"]
  end

  def measure(label)
    started_at = monotonic_time
    result = yield

    log_duration(
      label,
      monotonic_time - started_at
    )

    result
  end

  def log_duration(label, seconds)
    Rails.logger.info(
      "[AnalysisPerformance] #{label}: #{format('%.2f', seconds)}秒"
    )
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
