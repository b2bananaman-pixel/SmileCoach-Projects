# 商材を起点としたAIロープレでは練習テーマを使わないため、practice_theme_idのNULLを許可する（Issue #86）
#
# 既存のデータは変更・削除しない。外部キーとインデックスは、過去の履歴のために残す。
# AIロープレのセッションは、練習テーマと商材のどちらも持たない状態にならないよう、チェック制約で保証する。
#
# ロールバックの注意：
# 練習テーマのない行が作成された後は、NOT NULLに戻せないため、downは失敗する。
# ロールバックする場合は、練習テーマのない行の扱いを決めてから実行すること。
class MakePracticeThemeOptional < ActiveRecord::Migration[7.2]
  def up
    change_column_null :ai_roleplay_sessions, :practice_theme_id, true
    change_column_null :practices, :practice_theme_id, true

    add_check_constraint :ai_roleplay_sessions,
                         "practice_theme_id IS NOT NULL OR product_id IS NOT NULL",
                         name: "ai_roleplay_sessions_practice_theme_or_product_present"
  end

  def down
    remove_check_constraint :ai_roleplay_sessions, name: "ai_roleplay_sessions_practice_theme_or_product_present"

    change_column_null :practices, :practice_theme_id, false
    change_column_null :ai_roleplay_sessions, :practice_theme_id, false
  end
end
