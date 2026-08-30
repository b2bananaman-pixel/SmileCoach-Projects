class PracticesController < ApplicationController
  before_action :authenticate_user!

  def index
    @practices = current_user.practices
                             .includes(:analysis, :practice_theme)
                             .order(created_at: :desc)
  end

  def audio
    practice = current_user.practices.find(params[:id])

    practice.audio.purge

    redirect_to practices_path
  end
end
