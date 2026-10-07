class CreateAiRoleplayMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_roleplay_messages do |t|
      t.references :ai_roleplay_session, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false

      t.timestamps
    end
  end
end
