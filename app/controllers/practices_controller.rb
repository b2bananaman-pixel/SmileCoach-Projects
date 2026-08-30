class PracticesController < ApplicationController
  before_action :authenticate_user!

  def index
    @practices = current_user.practices
                             .includes(:analysis, :practice_theme)
                             .order(created_at: :desc)
  end
end
