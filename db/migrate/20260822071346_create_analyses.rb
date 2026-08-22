class CreateAnalyses < ActiveRecord::Migration[7.2]
  def change
    create_table :analyses do |t|
      t.references :practice, null: false, foreign_key: true
      t.integer :total_score
      t.integer :smile_score
      t.float :voice_brightness
      t.integer :voice_brightness_score
      t.float :voice_clarity
      t.integer :voice_clarity_score
      t.float :speech_speed
      t.integer :speech_speed_score
      t.integer :filler_count
      t.integer :filler_score
      t.float :volume
      t.integer :volume_score
      t.text :ai_comment

      t.timestamps
    end
  end
end
