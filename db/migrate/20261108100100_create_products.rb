# 商材情報（新人向け教材とAIロープレの会話・評価で利用する）
#
# カテゴリは物理削除しないため、外部キーは削除を制限する（ON DELETE CASCADEにしない）。
# 新規登録時は非公開とし、公開状態は専用の操作でのみ変更する。
class CreateProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :products do |t|
      t.references :product_category, null: false, foreign_key: true
      t.string :maker, limit: 100
      t.string :name, limit: 100, null: false
      t.string :official_url, limit: 500
      t.text :summary, null: false
      t.text :features
      t.text :pricing
      t.text :precautions
      t.text :proposal_points
      t.text :confirmation_items
      t.boolean :published, default: false, null: false
      t.integer :lock_version, default: 0, null: false

      t.timestamps
    end

    add_index :products, :published
    add_check_constraint :products, "btrim(name) <> ''", name: "products_name_present"
    add_check_constraint :products, "btrim(summary) <> ''", name: "products_summary_present"
  end
end
