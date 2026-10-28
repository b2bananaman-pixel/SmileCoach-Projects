# 管理者専用画面の基底コントローラ
#
# 管理者以外のログインユーザーには、管理画面の存在を知らせないよう404を返す。
# 未ログインの場合は、authenticate_user!によりログイン画面へリダイレクトする。
class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  private

  def require_admin!
    return if current_user.admin?

    render file: Rails.public_path.join("404.html"),
           status: :not_found,
           layout: false,
           content_type: "text/html"
  end
end
