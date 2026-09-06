class CreatePracticeService
  def initialize(user:, practice_theme:, audio:, duration:)
    @user = user
    @practice_theme = practice_theme
    @audio = audio
    @duration = duration
  end

  def call
    practice = create_practice
    transcription = transcribe(practice)
    practice.update!(transcription: transcription)

    volume = VolumeAnalysis.new(practice.audio).volume

    speech_duration = SpeechDurationAnalysis.new(
      practice.audio,
      duration: practice.duration
    ).speech_duration

    speech_analysis = SpeechAnalysis.new(
      transcription: practice.transcription,
      duration: practice.duration,
      speech_duration: speech_duration
    )

    score_analysis = ScoreAnalysis.new(
      speech_speed: speech_analysis.speech_speed,
      volume: volume,
      filler_score: speech_analysis.filler_score
    )

    analysis = practice.create_analysis!(
      volume: volume,
      volume_score: score_analysis.volume_score,
      speech_speed: speech_analysis.speech_speed,
      speech_speed_score: score_analysis.speech_speed_score,
      filler_count: speech_analysis.filler_count,
      total_score: score_analysis.total_score,
      filler_score: speech_analysis.filler_score
    )

    ai_comment = AiCommentService.new(analysis).call
    analysis.update!(ai_comment: ai_comment)

    practice
  end

  private

  def create_practice
    practice = Practice.new(
      user: @user,
      practice_theme: @practice_theme,
      duration: @duration
    )

    practice.audio.attach(@audio)
    practice.save!

    practice
  end

  def transcribe(practice)
    result = GroqTranscriptionService.new(practice.audio).call
    result["text"]
  end
end
