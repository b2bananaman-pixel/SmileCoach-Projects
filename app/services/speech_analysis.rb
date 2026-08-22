class SpeechAnalysis
  def initialize(transcription:, duration:)
    @transcription = transcription
    @duration = duration
  end

  def speech_speed
    return 0.0 if @duration.blank? || @duration <= 0

    @transcription.to_s.length.to_f / @duration
  end
end
