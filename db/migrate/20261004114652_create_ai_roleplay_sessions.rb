class CreateAiRoleplaySessions < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_roleplay_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :practice_theme, null: false, foreign_key: true
      t.float :duration
      t.string :end_reason
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end
  end
end
