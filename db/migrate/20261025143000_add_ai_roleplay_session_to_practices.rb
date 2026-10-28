class AddAiRoleplaySessionToPractices < ActiveRecord::Migration[7.2]
  def change
    # 通常録画のPracticeはNULLのまま残し、AIロープレ1回につき音声分析用Practiceを1件だけ関連付ける
    add_reference :practices,
                  :ai_roleplay_session,
                  foreign_key: true,
                  index: { unique: true }
  end
end
