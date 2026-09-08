class GuestAudioAnalysisService
  def initialize(audio:, duration:)
    @audio = audio
    @duration = duration.to_f
  end

  def call
    audio_file = create_tempfile

    transcription = transcribe(audio_file)

    volume = analyze_volume(audio_file)
    speech_duration = analyze_speech_duration(audio_file)

    speech_analysis = SpeechAnalysis.new(
      transcription: transcription,
      duration: @duration,
      speech_duration: speech_duration
    )

    score_analysis = ScoreAnalysis.new(
      speech_speed: speech_analysis.speech_speed,
      volume: volume,
      filler_score: speech_analysis.filler_score
    )

    result = GuestAnalysisResult.new(
      total_score: score_analysis.total_score,
      speech_speed: speech_analysis.speech_speed,
      speech_speed_score: score_analysis.speech_speed_score,
      filler_count: speech_analysis.filler_count,
      filler_score: speech_analysis.filler_score,
      volume: volume,
      volume_score: score_analysis.volume_score
    )

    begin
      ai_comment = AiCommentService.new(result).call
      result.ai_comment = ai_comment
    rescue StandardError => e
      Rails.logger.error(
        "ゲストのAIコメント生成に失敗しました: #{e.class}"
      )
    end

    result
  ensure
    audio_file&.close!
  end

  private

  def create_tempfile
    tempfile = Tempfile.new([ "guest_practice", ".webm" ])
    tempfile.binmode

    if @audio.respond_to?(:read)
      tempfile.write(@audio.read)
    else
      tempfile.write(@audio.to_s)
    end

    tempfile.flush
    tempfile
  end

  def transcribe(audio_file)
    GuestTranscriptionService.new(audio_file).call
  end

  def analyze_volume(audio_file)
    GuestVolumeAnalysis.new(audio_file).volume
  end

  def analyze_speech_duration(audio_file)
    GuestSpeechDurationAnalysis.new(
      audio_file,
      duration: @duration
    ).speech_duration
  end
end
