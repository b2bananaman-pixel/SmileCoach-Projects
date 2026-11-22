# 新規登録の招待の発行・一覧・取り消し（Issue #90）
#
# 管理者（admin・super_admin）だけが利用できる（Admin::BaseControllerで確認する）。
# 招待リンクは発行した直後のレスポンスでだけ表示し、一覧や他の画面・ログには出さない。
# リンクをリダイレクト先へ渡すとセッション（Cookie）に残るため、発行の結果はリダイレクトせずにその場で表示する。
class Admin::InvitationsController < Admin::BaseController
  REVOKE_FAILED_MESSAGE = "この招待は取り消せません（使用済み・取り消し済み・期限切れのいずれかです）。".freeze

  def index
    @invitations = Invitation.includes(:invited_by, :accepted_user).recent_first
    @now = Time.current
  end

  def new
    @invitation = Invitation.new
  end

  def create
    @invitation = Invitation.issue(email: invitation_params[:email], invited_by: current_user)

    unless @invitation.persisted?
      render :new, status: :unprocessable_entity
      return
    end

    # 招待リンクを含む画面は、ブラウザ・中間のキャッシュに保存させず、他のサイトへRefererを送らない
    #
    # no-referrerにすると、Turboで画面を移動した後も同じ文書にこの設定が残り、
    # 通常のフォーム送信でOriginが"null"になってCSRFのOrigin検証で拒否される（422）ため、same-originとする。
    # この画面のURL（POST /admin/invitations）には招待トークンが含まれないため、同じサイト内へのRefererは問題にならない。
    no_store
    response.headers["Referrer-Policy"] = "same-origin"

    @invitation_url = new_user_registration_url(invitation_token: @invitation.token)
    render :created, status: :created
  end

  def revoke
    invitation = Invitation.find(params[:id])
    invitation.revoke!

    redirect_to admin_invitations_path, notice: "#{invitation.email}への招待を取り消しました。", status: :see_other
  rescue Invitation::NotRevocableError
    redirect_to admin_invitations_path, alert: REVOKE_FAILED_MESSAGE, status: :see_other
  end

  private

  def invitation_params
    params.require(:invitation).permit(:email)
  end
end
