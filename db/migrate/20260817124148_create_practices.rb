class CreatePractices < ActiveRecord::Migration[7.2]
  def change
    create_table :practices do |t|
      t.references :user, null: false, foreign_key: true
      t.references :practice_theme, null: false, foreign_key: true

      t.timestamps
    end
  end
end
