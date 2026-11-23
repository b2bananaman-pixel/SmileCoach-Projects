# Deviseのアカウント登録・編集・削除
#
# 新規登録は、管理者が発行した有効な招待がある場合だけ行える（Issue #90）。
# 1. 招待リンク（GET /users/sign_up?invitation_token=...）を受け取ったら、トークンを検証して招待IDだけをセッションに保存し、
#    トークンを含まないURL（GET /users/sign_up）へ303でリダイレクトする（トークンはセッションに保存しない）
# 2. 登録フォームと登録（POST /users）は、セッションの招待IDが有効な招待を指す場合だけ利用できる
# 3. 登録時は招待の行をロックして有効性を再確認し、ユーザーの作成と招待の使用済み化を同じトランザクションで行う
# 招待がない・無効・期限切れ・使用済み・取り消し済みの場合は、同じメッセージでログイン画面へ移動する。
#
# 最後の最高管理者はアカウントを削除できない（Userのbefore_destroyで削除を中止する）。
# Devise標準のdestroyは削除の成否に関係なくログアウトして削除完了を表示するため、削除処理だけを差し替える。
class Users::RegistrationsController < Devise::RegistrationsController
  INVITATION_SESSION_KEY = "invitation_id".freeze
  INVALID_INVITATION_MESSAGE = "招待リンクが無効か有効期限が切れています".freeze

  before_action :protect_invitation_response, only: %i[new create]
  before_action :store_invitation_from_token, only: :new, if: -> { params.key?(:invitation_token) }
  before_action :require_usable_invitation, only: %i[new create]

  # 登録処理はDevise（5.0）標準のcreateと同じ。保存だけを、招待の行をロックして使用済みにする処理に置き換える
  def create
    build_resource(sign_up_params)
    accepted = @invitation.accept_with(resource)
    yield resource if block_given?

    unless accepted
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
      return
    end

    session.delete(INVITATION_SESSION_KEY)

    if resource.active_for_authentication?
      set_flash_message! :notice, :signed_up
      sign_up(resource_name, resource)
      respond_with resource, location: after_sign_up_path_for(resource)
    else
      set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
      expire_data_after_sign_in!
      respond_with resource, location: after_inactive_sign_up_path_for(resource)
    end
  rescue Invitation::NotUsableError
    # 登録フォームを表示した後に、招待が使用済み・取り消し済み・期限切れになった場合（同時登録を含む）
    reject_invitation
  end

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

  protected

  # 登録フォームのメールアドレスは、送信された値を使わず招待先のメールアドレスにする
  def build_resource(hash = {})
    super(hash.except(:email, "email"))
    resource.email = @invitation.email if @invitation
  end

  private

  # 招待先のメールアドレスを含む画面は、ブラウザ・中間のキャッシュに保存させず、他のサイトへRefererを送らない
  #
  # no-referrerにすると、Turboで画面を移動した後も同じ文書にこの設定が残り、
  # 通常のフォーム送信でOriginが"null"になってCSRFのOrigin検証で拒否される（422）ため、same-originとする（PR #136）。
  # トークンを含むURLは303でリダイレクトするだけで画面を表示しないため、その後のRefererにトークンは含まれない。
  def protect_invitation_response
    no_store
    response.headers["Referrer-Policy"] = "same-origin"
  end

  def store_invitation_from_token
    session.delete(INVITATION_SESSION_KEY)
    invitation = Invitation.find_usable_by_token(params[:invitation_token])
    return reject_invitation unless invitation

    session[INVITATION_SESSION_KEY] = invitation.id
    redirect_to new_user_registration_path, status: :see_other
  end

  def require_usable_invitation
    @invitation = Invitation.find_usable(session[INVITATION_SESSION_KEY])
    reject_invitation unless @invitation
  end

  def reject_invitation
    session.delete(INVITATION_SESSION_KEY)
    redirect_to new_user_session_path, alert: INVALID_INVITATION_MESSAGE, status: :see_other
  end
end
