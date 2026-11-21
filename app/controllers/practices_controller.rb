class PracticesController < ApplicationController
  before_action :authenticate_user!

  # 練習履歴にはAIロープレだけを表示する（通常録画はIssue #66で廃止した）
  #
  # 通常録画の過去データ（ai_roleplay_session_idのないPractice）がDBに残っていても表示しない。
  # AIロープレの音声分析用Practiceは、AIロープレの履歴として1セッションにつき1件で表示する。
  def index
    @history_items = current_user.ai_roleplay_sessions
                                 .includes(:practice_theme, :ai_roleplay_evaluation, practice: :analysis)
                                 .order(created_at: :desc, id: :desc)
                                 .to_a
  end
end
