# ログイン後のマイページ（ログイン済みの場合に / で表示する）
class MypagesController < ApplicationController
  before_action :authenticate_user!

  def show
    @recent_practice = recent_practice
  end

  private

  # 練習履歴画面と同じく、AIロープレと通常録画のうち最も新しい1件を返す（記録がない場合はnil）
  #
  # それぞれ本人の最新1件だけを取得し、作成日時が同じ場合はIDの大きいほうを新しいものとする。
  # AIロープレの音声分析用Practiceは、AIロープレの記録として扱うため通常録画から除く。
  def recent_practice
    latest_ai_roleplay_session = current_user.ai_roleplay_sessions
                                             .includes(:practice_theme)
                                             .order(created_at: :desc, id: :desc)
                                             .first

    latest_practice = current_user.practices
                                  .where(ai_roleplay_session_id: nil)
                                  .includes(:practice_theme, :analysis)
                                  .order(created_at: :desc, id: :desc)
                                  .first

    [ latest_ai_roleplay_session, latest_practice ].compact.max_by { |item| [ item.created_at, item.id ] }
  end
end
