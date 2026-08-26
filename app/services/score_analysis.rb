class ScoreAnalysis
  def initialize(speech_speed:, volume:)
    @speech_speed = speech_speed.to_f
    @volume = volume.to_f
  end

  def speech_speed_score
    return 0 if @speech_speed <= 0

    case @speech_speed
    when 3.0..5.0
      100
    when 2.0...3.0, 5.0...6.0
      80
    when 1.5...2.0, 6.0...6.5
      60
    when 1.0...1.5, 6.5...7.0
      40
    when 0.0...1.0, (7.0...)
      20
    else
      0
    end
  end

  def volume_score
    case @volume
    when -20.0..-10.0
      100
    when -25.0...-20.0
      80
    when -30.0...-25.0
      60
    when -35.0...-30.0
      40
    when -45.0...-35.0
      20
    else
      0
    end
  end

  def total_score
    ((speech_speed_score + volume_score) / 2.0).round
  end
end
