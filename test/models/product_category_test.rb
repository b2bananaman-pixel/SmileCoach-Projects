require "test_helper"

class ProductCategoryTest < ActiveSupport::TestCase
  test "カテゴリ名があれば有効なカテゴリとして登録できる" do
    product_category = ProductCategory.create!(name: "ネットテレビ")

    assert product_category.active?
    assert_equal 0, product_category.lock_version
  end

  test "カテゴリ名は必須" do
    [ nil, "", "   ", "　" ].each do |name|
      product_category = ProductCategory.new(name: name)

      assert_not product_category.valid?
      assert_includes product_category.errors.full_messages, "カテゴリ名を入力してください"
    end
  end

  test "カテゴリ名は50文字以内" do
    assert ProductCategory.new(name: "あ" * 50).valid?

    product_category = ProductCategory.new(name: "あ" * 51)

    assert_not product_category.valid?
    assert_includes product_category.errors.full_messages, "カテゴリ名は50文字以内で入力してください"
  end

  test "前後の空白（全角スペースを含む）を除去し、全角英数字を半角に統一して保存する" do
    product_category = ProductCategory.create!(name: "　 ＷｉＦｉ　サービス \n")

    assert_equal "WiFi サービス", product_category.reload.name
  end

  test "空白・全角半角・大文字小文字の違いだけの名前は重複として登録できない" do
    ProductCategory.create!(name: "WiFi")

    [ "WiFi", " WiFi ", "ＷｉＦｉ", "wifi", "WIFI", "ｗｉｆｉ" ].each do |name|
      product_category = ProductCategory.new(name: name)

      assert_not product_category.valid?, "#{name.inspect}は重複として扱う"
      assert_includes product_category.errors.full_messages, "カテゴリ名はすでに使用されています"
    end
  end

  test "半角カタカナと全角カタカナの違いだけの名前は重複として登録できない" do
    product_category = ProductCategory.new(name: "ｲﾝﾀｰﾈｯﾄ")

    assert_not product_category.valid?
    assert_includes product_category.errors.full_messages, "カテゴリ名はすでに使用されています"
  end

  test "バリデーションを通さない場合も、DBの一意制約で大文字小文字の違いだけの重複を防ぐ" do
    ProductCategory.create!(name: "WiFi")

    assert_raises(ActiveRecord::RecordNotUnique) do
      ProductCategory.new(name: "wifi").save!(validate: false)
    end
  end

  test "DBのCHECK制約で空白だけのカテゴリ名を防ぐ" do
    assert_raises(ActiveRecord::StatementInvalid) do
      ProductCategory.connection.execute("INSERT INTO product_categories (name, created_at, updated_at) VALUES (' ', NOW(), NOW())")
    end
  end

  test "自分自身の名前のまま更新できる" do
    product_category = product_categories(:internet)

    assert product_category.update(name: "インターネット")
  end

  test "activeスコープは有効なカテゴリだけを返す" do
    assert_includes ProductCategory.active, product_categories(:internet)
    assert_not_includes ProductCategory.active, product_categories(:inactive)
  end

  test "新規商材の選択肢は有効なカテゴリだけ" do
    categories = ProductCategory.selectable_for(Product.new)

    assert_includes categories, product_categories(:internet)
    assert_not_includes categories, product_categories(:inactive)
  end

  test "既存商材の選択肢には、保存済みの無効なカテゴリも含め、他の無効なカテゴリは含めない" do
    other_inactive = ProductCategory.create!(name: "別の旧サービス", active: false)

    categories = ProductCategory.selectable_for(products(:legacy))

    assert_includes categories, product_categories(:inactive)
    assert_includes categories, product_categories(:internet)
    assert_not_includes categories, other_inactive
  end

  test "無効なカテゴリは表示名に（無効）を付ける" do
    assert_equal "インターネット", product_categories(:internet).display_name
    assert_equal "旧サービス（無効）", product_categories(:inactive).display_name
  end

  test "無効にしても既存商材との関連付けを維持する" do
    product_category = product_categories(:internet)

    product_category.update!(active: false)

    assert_equal product_category, products(:fiber).reload.product_category
  end

  test "商材があるカテゴリは削除できない" do
    product_category = product_categories(:internet)

    assert_not product_category.destroy
    assert ProductCategory.exists?(product_category.id)
  end

  test "同時に編集した場合、後から保存した変更は楽観的ロックで拒否される" do
    first = ProductCategory.find(product_categories(:internet).id)
    second = ProductCategory.find(product_categories(:internet).id)

    first.update!(name: "光回線")

    assert_raises(ActiveRecord::StaleObjectError) { second.update!(name: "インターネット回線") }
    assert_equal "光回線", product_categories(:internet).reload.name
  end

  test "seed_defaults!で初期カテゴリ4種類を登録し、再実行しても重複しない" do
    created_count = ProductCategory.seed_defaults!

    # fixtureに「インターネット」「カード」があるため、残りの2件だけを登録する
    assert_equal 2, created_count
    ProductCategory::DEFAULT_NAMES.each do |name|
      assert_equal 1, ProductCategory.where(name: name).count
    end

    assert_no_difference("ProductCategory.count") do
      assert_equal 0, ProductCategory.seed_defaults!
    end
  end

  test "seed_defaults!は既存カテゴリの有効・無効の状態を変更しない" do
    product_categories(:internet).update!(active: false)

    ProductCategory.seed_defaults!

    assert_not product_categories(:internet).reload.active?
  end
end
