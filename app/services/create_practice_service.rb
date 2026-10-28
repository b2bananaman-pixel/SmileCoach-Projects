class CreatePracticeService
  include AnalysisPerformanceMeasurement

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

    PracticeAnalysisService.new(practice).call

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
end
