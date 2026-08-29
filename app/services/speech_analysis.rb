class SpeechAnalysis
  FILLERS = %w[
    えーと
    ええと
    えっと
    あのー
    そのー
    えー
    ええ
    あの
    その
    まあ
  ].freeze

  def initialize(transcription:, duration:)
    @transcription = transcription
    @duration = duration
  end

  def speech_speed
    return 0.0 if @duration.blank? || @duration <= 0

    @transcription.to_s.length.to_f / @duration
  end

  def filler_count
    text = @transcription.to_s
    pattern = Regexp.union(FILLERS.sort_by { |filler| -filler.length })

    text.scan(pattern).length
  end

  def filler_count_per_minute
    return 0.0 if @duration.blank? || @duration <= 0

    filler_count / (@duration / 60.0)
  end

    def filler_score
    average = filler_count_per_minute

    return 0 if @duration.blank? || @duration <= 0

    case average
    when 0...1
      100
    when 1...2
      80
    when 2...4
      60
    when 4...6
      40
    else
      20
    end
  end
end
