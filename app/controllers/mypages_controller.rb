# ログイン後のマイページ（ログイン済みの場合に / で表示する）
class MypagesController < ApplicationController
  before_action :authenticate_user!

  def show
    @recent_practice = recent_practice
  end

  private

  # 練習履歴画面と同じく、本人のAIロープレのうち最も新しい1件を返す（記録がない場合はnil）
  #
  # 作成日時が同じ場合はIDの大きいほうを新しいものとする。
  # 通常録画はIssue #66で廃止したため、過去データがDBに残っていても表示しない。
  def recent_practice
    current_user.ai_roleplay_sessions
                .includes(:practice_theme)
                .order(created_at: :desc, id: :desc)
                .first
  end
end
