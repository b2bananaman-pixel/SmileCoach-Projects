require "test_helper"

class PracticeCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "有効なカテゴリだけを表示し、無効なカテゴリは表示しない" do
    sign_in @user

    get practice_categories_path

    assert_response :success
    assert_select "h1", "練習カテゴリを選択"
    assert_select "[data-practice-category='#{product_categories(:internet).id}'] h2", "インターネット"
    assert_select "[data-practice-category='#{product_categories(:card).id}'] h2", "カード"
    assert_select "[data-practice-category='#{product_categories(:inactive).id}']", 0
    assert_select "[data-practice-category]", 2
    assert_select "a[href=?]", practice_category_path(product_categories(:card)), text: "このカテゴリを選ぶ"
  end

  test "公開中の商材が0件の有効なカテゴリも表示し、準備中と表示する" do
    sign_in @user

    get practice_categories_path

    # インターネットの商材（光回線プラン）は非公開
    assert_select "[data-practice-category='#{product_categories(:internet).id}'] [data-practice-category-status]", "準備中"
    assert_select "[data-practice-category='#{product_categories(:card).id}'] [data-practice-category-status]", "商材 1件"
  end

  test "管理画面でのカテゴリ名の変更・追加・無効化が一覧に反映される" do
    sign_in @user
    product_categories(:card).update!(name: "クレジットカード")
    added = ProductCategory.create!(name: "ネットテレビ")
    product_categories(:internet).update!(active: false)

    get practice_categories_path

    assert_select "[data-practice-category='#{product_categories(:card).id}'] h2", "クレジットカード"
    assert_select "[data-practice-category='#{added.id}'] h2", "ネットテレビ"
    assert_select "[data-practice-category='#{product_categories(:internet).id}']", 0
  end

  test "有効なカテゴリが0件の場合は案内を表示する" do
    sign_in @user
    ProductCategory.update_all(active: false)

    get practice_categories_path

    assert_response :success
    assert_select "[data-practice-categories-empty]", /現在、練習できるカテゴリはありません。/
    assert_select "[data-practice-category]", 0
  end

  test "カテゴリが増えても一覧の取得クエリ数は変わらない" do
    sign_in @user
    get practice_categories_path

    few_count = count_queries { get practice_categories_path }

    3.times do |i|
      category = ProductCategory.create!(name: "追加カテゴリ#{i}")
      Product.create!(product_category: category, name: "追加商材#{i}", summary: "概要").update!(published: true)
    end
    many_count = count_queries { get practice_categories_path }

    assert_equal few_count, many_count
  end

  test "カテゴリの商材選択画面には、そのカテゴリの公開中の商材だけを表示する" do
    sign_in @user
    other = Product.create!(product_category: product_categories(:internet), name: "他カテゴリの商材", summary: "概要")
    other.update!(published: true)
    Product.create!(product_category: product_categories(:card), name: "非公開のカード", summary: "概要")

    get practice_category_path(product_categories(:card))

    assert_response :success
    assert_select "h1", "カード"
    assert_select "[data-practice-product]", 1
    assert_select "[data-practice-product='#{products(:published_card).id}'] h2", "ポイントカード"
    assert_select "a[href=?]", product_ai_roleplay_path(products(:published_card)), text: "この商材でAIロープレを始める"
    assert_not_includes response.body, "他カテゴリの商材"
    assert_not_includes response.body, "非公開のカード"
    assert_select "[data-practice-category-empty]", 0
    assert_select "a[data-back-to-categories][href=?]", practice_categories_path
  end

  test "商材が0件・非公開の商材だけのカテゴリは準備中の案内を表示する" do
    sign_in @user
    empty_category = ProductCategory.create!(name: "ネットテレビ")

    [ empty_category, product_categories(:internet) ].each do |category|
      get practice_category_path(category)

      assert_response :success
      assert_select "[data-practice-category-empty]", "現在、このカテゴリの練習は準備中です"
      assert_select "[data-practice-product]", 0
    end
  end

  # 404の例外ではログイン状態のセッションが保存されないため、リクエストごとにログインする
  test "無効なカテゴリ・存在しないカテゴリ・不正な形式のIDは404を返す" do
    max_id = ProductCategory.maximum(:id)

    [ product_categories(:inactive).id.to_s, (max_id + 1).to_s, "abc", "#{max_id}abc", "0", "-1", "9" * 20 ].each do |id|
      sign_in @user
      get "/practice_categories/#{ERB::Util.url_encode(id)}"

      assert_response :not_found, id
    end
  end

  test "カテゴリが無効になると商材選択画面は404になり、その商材からAIロープレを開始できない" do
    sign_in @user
    product_categories(:card).update!(active: false)

    get practice_category_path(product_categories(:card))
    assert_response :not_found

    sign_in @user
    get product_ai_roleplay_path(products(:published_card))
    assert_response :not_found
  end

  test "未ログインの場合はログイン画面へリダイレクトする" do
    get practice_categories_path
    assert_redirected_to new_user_session_path

    get practice_category_path(product_categories(:card))
    assert_redirected_to new_user_session_path
  end

  test "カテゴリ選択から商材選択を経てAIロープレ画面を表示できる" do
    sign_in @user

    get practice_categories_path
    get practice_category_path(product_categories(:card))
    get product_ai_roleplay_path(products(:published_card))

    assert_response :success
    assert_select "[data-ai-roleplay-category]", /カード/
    assert_select "[data-ai-roleplay-product]", /ポイントカード/
    assert_select "[data-ai-roleplay-product-snapshot-token-value]", 1
  end

  private

  def count_queries(&block)
    # テストでは前のリクエストのクエリキャッシュが残るため、キャッシュから返ったものも含めて数える
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
