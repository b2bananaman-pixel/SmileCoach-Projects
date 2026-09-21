class AnalysesController < ApplicationController
  before_action :authenticate_user!

  def show
    @analysis = current_user.practices
                            .joins(:analysis)
                            .find_by!(analyses: { id: params[:id] })
                            .analysis

    @speech_segments = SpeechSegmentsAnalysis.new(
      @analysis.practice.audio,
      duration: @analysis.practice.duration
    ).speech_segments
  end

  def smile_score
    analysis = current_user.practices
                           .joins(:analysis)
                           .find_by!(analyses: { id: params[:id] })
                           .analysis

    if params[:smile_score].present?
      score = params[:smile_score].to_i
      return head :unprocessable_entity unless score.between?(0, 100)

      total_score =
        (
          analysis.speech_speed_score +
          analysis.filler_score +
          analysis.volume_score +
          score
        ) / 4.0

      analysis.update!(
        smile_score: score,
        total_score: total_score.round
      )
    else
      total_score =
        (
          analysis.speech_speed_score +
          analysis.filler_score +
          analysis.volume_score
        ) / 3.0

      analysis.update!(
        smile_score: nil,
        total_score: total_score.round
      )
    end

    render json: {
      smile_score: analysis.smile_score,
      total_score: analysis.total_score
    }
  end
end
