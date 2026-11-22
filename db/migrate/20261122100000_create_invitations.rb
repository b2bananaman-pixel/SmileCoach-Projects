# 管理者が発行する新規登録の招待（Issue #90）
#
# - 招待トークンはDBに保存せず、SHA-256のダイジェスト（16進数64文字）だけを保存する
# - 発行者・登録したユーザーが削除されても招待の履歴を残すため、外部キーは ON DELETE SET NULL とする
# - 未使用かつ取り消していない招待は、同じメールアドレスにつき1件までとする（部分一意インデックス）
# - 使用（accepted_at）と取り消し（revoked_at）は同時に設定できない
class CreateInvitations < ActiveRecord::Migration[7.2]
  def change
    create_table :invitations do |t|
      t.string :email, null: false
      t.string :token_digest, null: false
      t.references :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.references :accepted_user, index: { unique: true }, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :invitations, :token_digest, unique: true
    add_index :invitations, :email
    add_index :invitations, :email,
              unique: true,
              where: "accepted_at IS NULL AND revoked_at IS NULL",
              name: "index_invitations_on_email_pending_unique"

    add_check_constraint :invitations, "email = lower(btrim(email)) AND email <> ''", name: "invitations_email_normalized"
    add_check_constraint :invitations, "token_digest ~ '^[0-9a-f]{64}$'", name: "invitations_token_digest_format"
    add_check_constraint :invitations, "expires_at > created_at", name: "invitations_expires_after_created"
    add_check_constraint :invitations, "accepted_at IS NULL OR revoked_at IS NULL", name: "invitations_not_accepted_and_revoked"
    # 登録したユーザーが削除された場合は accepted_user_id だけがNULLになるため、逆方向（使用日時なしでユーザーあり）だけを禁止する
    add_check_constraint :invitations, "accepted_user_id IS NULL OR accepted_at IS NOT NULL", name: "invitations_accepted_user_requires_accepted_at"
  end
end
