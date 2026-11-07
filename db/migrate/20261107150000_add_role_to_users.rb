# usersに権限（role）を追加し、既存の管理者（admin = true）をrole = admin（1）へ移行する
#
# 旧adminカラムは、旧コードに戻した場合でも管理者が管理画面を使えるよう削除せずに残す。
# カラム追加とデータ移行を1つのマイグレーションにまとめ、PostgreSQLのトランザクション内で同時に反映する。
# アプリのUserモデル（enum・ignored_columns）の影響を受けないよう、データ移行はSQLで行う。
class AddRoleToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :role, :integer, default: 0, null: false
    add_index :users, :role
    add_check_constraint :users, "role IN (0, 1, 2)", name: "users_role_check"

    # super_adminへの自動昇格は行わない
    execute "UPDATE users SET role = 1 WHERE admin = TRUE"
  end

  # ロールバック時は、admin・super_adminのユーザーをadmin = trueへ書き戻してから、roleを削除する
  # 旧adminカラムは真偽値のため、super_adminとadminの区別は失われる（再度マイグレーションするとadminになる）
  def down
    execute "UPDATE users SET admin = TRUE WHERE role IN (1, 2)"

    remove_check_constraint :users, name: "users_role_check"
    remove_index :users, :role
    remove_column :users, :role
  end
end
