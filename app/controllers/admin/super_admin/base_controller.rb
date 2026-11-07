# 最高管理者専用画面の基底コントローラ
#
# Admin::BaseControllerの確認（ログイン・管理者権限）の後に、最高管理者であることを確認する。
# 管理者（admin）にも最高管理者専用画面の存在を知らせないよう404を返す。
class Admin::SuperAdmin::BaseController < Admin::BaseController
  before_action :require_super_admin!

  private

  def require_super_admin!
    return if current_user.super_admin?

    render_not_found
  end
end
