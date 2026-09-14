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

    score = params[:smile_score].to_i
    return head :unprocessable_entity unless score.between?(0, 100)

    analysis.update!(smile_score: score)

    render json: { smile_score: analysis.smile_score }
  end
end
