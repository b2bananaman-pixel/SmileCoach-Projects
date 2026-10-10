class CreateAiRoleplayEvaluations < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_roleplay_evaluations do |t|
      t.references :ai_roleplay_session,
                   null: false,
                   foreign_key: true,
                   index: { unique: true }

      t.integer :hearing_score
      t.text :hearing_good_point
      t.text :hearing_improvement_point

      t.integer :listening_score
      t.text :listening_good_point
      t.text :listening_improvement_point

      t.integer :needs_score
      t.text :needs_good_point
      t.text :needs_improvement_point

      t.integer :proposal_score
      t.text :proposal_good_point
      t.text :proposal_improvement_point

      t.integer :closing_score
      t.text :closing_good_point
      t.text :closing_improvement_point

      t.integer :reference_score

      t.text :overall_strength
      t.text :priority_improvement
      t.text :next_practice_goal

      t.timestamps
    end
  end
end
