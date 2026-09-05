require "natto"

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

  SMALL_KANA = "ァィゥェォャュョヮ".freeze

  def initialize(transcription:, duration:, speech_duration: nil)
    @transcription = transcription
    @duration = duration
    @speech_duration = speech_duration
  end

  def speech_speed
    duration = @speech_duration || @duration

    return 0.0 if duration.blank? || duration <= 0

    mora_count.to_f / duration
  end

  def mora_count
    nm = Natto::MeCab.new
    reading = +""

    nm.parse(@transcription.to_s) do |node|
      value = node.feature.split(",")[7]
      reading << value if value.present? && value != "*"
    end

    count_mora(reading)
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

  private

  def count_mora(reading)
    reading
      .gsub(/[#{SMALL_KANA}]/, "")
      .scan(/[ァ-ヴー]/)
      .length
  end
end
