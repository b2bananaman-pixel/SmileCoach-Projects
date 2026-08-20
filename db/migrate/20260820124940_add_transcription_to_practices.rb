class AddTranscriptionToPractices < ActiveRecord::Migration[7.2]
  def change
    add_column :practices, :transcription, :text
  end
end
