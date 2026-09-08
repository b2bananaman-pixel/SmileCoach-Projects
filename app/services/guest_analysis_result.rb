class GuestAnalysisResult
  attr_accessor :total_score,
                :speech_speed,
                :speech_speed_score,
                :filler_count,
                :filler_score,
                :volume,
                :volume_score,
                :ai_comment

  def initialize(
    total_score:,
    speech_speed:,
    speech_speed_score:,
    filler_count:,
    filler_score:,
    volume:,
    volume_score:,
    ai_comment: nil
  )
    @total_score = total_score
    @speech_speed = speech_speed
    @speech_speed_score = speech_speed_score
    @filler_count = filler_count
    @filler_score = filler_score
    @volume = volume
    @volume_score = volume_score
    @ai_comment = ai_comment
  end
end
