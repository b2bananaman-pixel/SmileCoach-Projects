class AnalysesController < ApplicationController
  before_action :authenticate_user!

  def show
    @analysis = current_user.practices
                            .joins(:analysis)
                            .find_by!(analyses: { id: params[:id] })
                            .analysis
  end
end
