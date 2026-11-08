# AIロープレで使用した商材と、練習開始時点の商材情報（スナップショット）を保存する
#
# 商材の選択は任意のため、既存のセッションを含めてNULLを許可する。
# 商材IDとスナップショットは、両方あるか両方ないかのどちらかとする。
# 商材は物理削除しないため、外部キーは削除を制限する（ON DELETE CASCADEにしない）。
class AddProductToAiRoleplaySessions < ActiveRecord::Migration[7.2]
  def change
    add_reference :ai_roleplay_sessions, :product, null: true, foreign_key: true
    add_column :ai_roleplay_sessions, :product_snapshot, :jsonb

    add_check_constraint :ai_roleplay_sessions,
                         "(product_id IS NULL) = (product_snapshot IS NULL)",
                         name: "ai_roleplay_sessions_product_snapshot_presence"
    add_check_constraint :ai_roleplay_sessions,
                         "product_snapshot IS NULL OR jsonb_typeof(product_snapshot) = 'object'",
                         name: "ai_roleplay_sessions_product_snapshot_object"
  end
end
