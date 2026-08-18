class PracticeThemesController < ApplicationController
  before_action :authenticate_user!

  def index
    @practice_themes = PracticeTheme.all
  end

  def show
    @practice_theme = PracticeTheme.find(params[:id])
  end

  def create_practice
    practice_theme = PracticeTheme.find(params[:id])

    practice = Practice.new(
      user: current_user,
      practice_theme: practice_theme
    )

    practice.audio.attach(params[:audio])
    practice.save!

    render json: { success: true, practice_id: practice.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end
end
