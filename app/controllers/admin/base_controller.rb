# 管理者専用画面の基底コントローラ
#
# 管理者（admin・super_admin）以外のログインユーザーには、管理画面の存在を知らせないよう404を返す。
# 未ログインの場合は、authenticate_user!によりログイン画面へリダイレクトする。
class Admin::BaseController < ApplicationController
  # 楽観的ロック（lock_version）で同時編集の競合を検出したときのメッセージ
  STALE_RECORD_MESSAGE = "他の管理者が先に更新したため、保存できませんでした。画面を再読み込みして最新の内容を確認してから、もう一度編集してください。".freeze

  before_action :authenticate_user!
  before_action :require_admin!

  private

  def require_admin!
    return if current_user.admin_access?

    render_not_found
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"),
           status: :not_found,
           layout: false,
           content_type: "text/html"
  end
end
