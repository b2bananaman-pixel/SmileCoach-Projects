class PracticesController < ApplicationController
  before_action :authenticate_user!

  def index
    # AIロープレの音声分析用Practiceは、AIロープレの履歴として表示するため通常録画から除く
    practices = current_user.practices
                            .where(ai_roleplay_session_id: nil)
                            .with_attached_audio
                            .includes(:analysis, :practice_theme)

    # 音声分析の有無に関係なく、AIロープレは1セッションにつき1件として表示する
    ai_roleplay_sessions = current_user.ai_roleplay_sessions
                                       .includes(:practice_theme, :ai_roleplay_evaluation, practice: :analysis)

    # 通常録画とAIロープレを1つの履歴として新しい順に並べる（同時刻の場合はIDの大きい順）
    @history_items = (practices.to_a + ai_roleplay_sessions.to_a)
                     .sort_by { |item| [ item.created_at, item.id ] }
                     .reverse
  end

  def audio
    practice = current_user.practices.find(params[:id])

    practice.audio.purge

    redirect_to practices_path
  end
end
