class ScoreAnalysis
  def initialize(speech_speed:, volume:, filler_score: 0)
    @speech_speed = speech_speed.to_f
    @volume = volume.to_f
    @filler_score = filler_score.to_i
  end

  def speech_speed_score
    return 0 if @speech_speed <= 0

    if @speech_speed.between?(5.0, 6.0)
      100
    elsif @speech_speed >= 4.0 && @speech_speed < 5.0 ||
          @speech_speed > 6.0 && @speech_speed < 7.0
      80
    elsif @speech_speed >= 3.0 && @speech_speed < 4.0 ||
          @speech_speed >= 7.0 && @speech_speed < 8.0
      60
    elsif @speech_speed >= 2.0 && @speech_speed < 3.0 ||
          @speech_speed >= 8.0 && @speech_speed < 9.0
      40
    else
      20
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
    ((speech_speed_score + @filler_score + volume_score) / 3.0).round
  end
end
