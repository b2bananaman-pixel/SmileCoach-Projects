class AddDurationToPractices < ActiveRecord::Migration[7.2]
  def change
    add_column :practices, :duration, :float
  end
end
