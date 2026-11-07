# Deviseのアカウント登録・編集・削除
#
# 最後の最高管理者はアカウントを削除できない（Userのbefore_destroyで削除を中止する）。
# Devise標準のdestroyは削除の成否に関係なくログアウトして削除完了を表示するため、削除処理だけを差し替える。
class Users::RegistrationsController < Devise::RegistrationsController
  # 削除できた場合の処理は、Devise（5.0）標準のdestroyと同じ
  def destroy
    unless resource.destroy
      redirect_to edit_user_registration_path,
                  alert: User::LAST_SUPER_ADMIN_ERROR_MESSAGE,
                  status: :see_other
      return
    end

    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    set_flash_message! :notice, :destroyed
    yield resource if block_given?
    respond_with_navigational(resource) { redirect_to after_sign_out_path_for(resource_name), status: Devise.responder.redirect_status }
  end
end
