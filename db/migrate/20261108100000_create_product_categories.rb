# 商材のカテゴリ（管理者が追加・編集する）
#
# カテゴリ名はモデルで前後の空白除去・全角半角の統一（NFKC）を行ってから保存し、
# 大文字・小文字の違いはLOWER(name)の一意インデックスで重複として扱う。
class CreateProductCategories < ActiveRecord::Migration[7.2]
  def change
    create_table :product_categories do |t|
      t.string :name, limit: 50, null: false
      t.boolean :active, default: true, null: false
      t.integer :lock_version, default: 0, null: false

      t.timestamps
    end

    add_index :product_categories, "LOWER(name)", unique: true, name: "index_product_categories_on_lower_name"
    add_check_constraint :product_categories, "btrim(name) <> ''", name: "product_categories_name_present"
  end
end
