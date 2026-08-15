class CreatePracticeThemes < ActiveRecord::Migration[7.2]
  def change
    create_table :practice_themes do |t|
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end
