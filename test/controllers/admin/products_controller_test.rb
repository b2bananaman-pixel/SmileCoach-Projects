require "test_helper"

class Admin::ProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @super_admin = users(:super_admin)
    @user = users(:two)
    @product = products(:fiber)
    @product_category = product_categories(:internet)
  end

  test "商材管理のルーティングに削除はない" do
    assert_equal "/admin/products", admin_products_path
    assert_recognizes({ controller: "admin/products", action: "publish", id: "1" },
                      { path: "/admin/products/1/publish", method: :patch })
    assert_recognizes({ controller: "admin/products", action: "unpublish", id: "1" },
                      { path: "/admin/products/1/unpublish", method: :patch })

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/admin/products/1", method: :delete)
    end
  end

  test "管理者は商材一覧でカテゴリと公開状態を確認できる" do
    sign_in @admin

    get admin_products_path

    assert_response :success
    assert_select "title", text: "商材一覧"
    assert_select "tr[data-product-id='#{@product.id}']" do
      assert_select "a[href='#{admin_product_path(@product)}']", text: "光回線プラン"
      assert_select "td", text: "インターネット"
      assert_select "[data-product-published-badge]", text: "非公開"
    end
    assert_select "tr[data-product-id='#{products(:published_card).id}'] [data-product-published-badge]", text: "公開"
    assert_select "tr[data-product-id='#{products(:legacy).id}'] td", text: "旧サービス（無効）"
  end

  test "最高管理者も商材を管理できる" do
    sign_in @super_admin

    get admin_products_path
    assert_response :success
    get admin_product_path(@product)
    assert_response :success
  end

  test "管理者は商材の詳細を確認でき、公式サイトURLは別タブで開くリンクになる" do
    sign_in @admin

    get admin_product_path(@product)

    assert_response :success
    assert_select "h1", text: "光回線プラン"
    assert_select "[data-product-category]", text: "インターネット"
    assert_select "a[href='https://example.com/fiber'][target='_blank'][rel='noopener noreferrer']"
    assert_select "[data-product-attribute=pricing]", text: "月額5,000円（2年契約）"
    assert_select "[data-product-attribute=features]", text: "未登録"
    assert_select "button", text: "公開する"
  end

  test "商材の詳細では入力内容のHTMLをエスケープして表示する" do
    sign_in @admin
    @product.update!(features: "<script>alert(1)</script>\n2行目")

    get admin_product_path(@product)

    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "検証を通さずに保存された不正な公式サイトURLは、リンクにせず文字として表示する" do
    sign_in @admin
    @product.update_column(:official_url, "javascript:alert(1)")

    get admin_product_path(@product)

    assert_response :success
    assert_select "a[href^='javascript']", count: 0
    assert_select "dd", text: "javascript:alert(1)"
  end

  test "新規登録画面のカテゴリの選択肢は有効なカテゴリだけで、公開状態の入力欄はない" do
    sign_in @admin

    get new_admin_product_path

    assert_response :success
    assert_select "select[name='product[product_category_id]']" do
      assert_select "option[value='#{@product_category.id}']", text: "インターネット"
      assert_select "option[value='#{product_categories(:card).id}']"
      assert_select "option[value='#{product_categories(:inactive).id}']", count: 0
    end
    assert_select "[name='product[published]']", count: 0
    assert_select "[name='product[lock_version]']", count: 0
  end

  test "管理者は商材を登録でき、新規登録時は非公開になる" do
    sign_in @admin

    assert_difference("Product.count", 1) do
      post admin_products_path, params: { product: {
        product_category_id: @product_category.id, maker: "サンプル通信", name: "モバイルWi-Fi",
        official_url: "https://example.com/wifi", summary: "持ち運びできるWi-Fiルーター。",
        features: "どこでも使える", pricing: "月額3,000円", precautions: "通信量の上限あり",
        proposal_points: "外出が多い方に提案する", confirmation_items: "利用場所を確認する"
      } }
    end

    product = Product.last
    assert_redirected_to admin_product_path(product)
    assert_not product.published?
    assert_equal @product_category, product.product_category
    assert_equal "利用場所を確認する", product.confirmation_items
    follow_redirect!
    assert_select ".alert", text: "商材を登録しました"
  end

  test "任意項目が空欄でも商材を登録できる" do
    sign_in @admin

    assert_difference("Product.count", 1) do
      post admin_products_path, params: { product: {
        product_category_id: @product_category.id, name: "モバイルWi-Fi", summary: "持ち運びできるWi-Fiルーター。",
        maker: "", official_url: "", features: "", pricing: "", precautions: "", proposal_points: "", confirmation_items: ""
      } }
    end
  end

  test "登録時にpublished・lock_versionを送信しても無視され、非公開で登録される" do
    sign_in @admin

    post admin_products_path, params: { product: {
      product_category_id: @product_category.id, name: "モバイルWi-Fi", summary: "概要", published: true, lock_version: 10
    } }

    product = Product.last
    assert_not product.published?
    assert_equal 0, product.lock_version
  end

  test "必須項目が未入力・URLが不正な場合は登録できず、日本語のエラーを表示する" do
    sign_in @admin

    assert_no_difference("Product.count") do
      post admin_products_path, params: { product: { product_category_id: "", name: "", summary: "", official_url: "javascript:alert(1)" } }
    end

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors]" do
      assert_select "li", text: "カテゴリを選択してください"
      assert_select "li", text: "商材名を入力してください"
      assert_select "li", text: "概要を入力してください"
      assert_select "li", text: "公式サイトURLはhttp://またはhttps://から始まるURLを入力してください"
    end
  end

  test "無効なカテゴリを指定した不正な登録はできない" do
    sign_in @admin

    assert_no_difference("Product.count") do
      post admin_products_path, params: { product: { product_category_id: product_categories(:inactive).id, name: "商材", summary: "概要" } }
    end

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: "カテゴリは無効なため選択できません"
    assert_select "option[value='#{product_categories(:inactive).id}']", count: 0
  end

  test "存在しないカテゴリを指定した登録はできない" do
    sign_in @admin

    assert_no_difference("Product.count") do
      post admin_products_path, params: { product: { product_category_id: 0, name: "商材", summary: "概要" } }
    end

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: "カテゴリを選択してください"
  end

  test "管理者は商材を編集できる" do
    sign_in @admin

    get edit_admin_product_path(@product)
    assert_response :success
    assert_select "input[name='product[lock_version]'][value='0']"
    assert_select "[name='product[published]']", count: 0

    patch admin_product_path(@product), params: { product: { name: "光回線プラン（新）", product_category_id: product_categories(:card).id, lock_version: 0 } }

    assert_redirected_to admin_product_path(@product)
    @product.reload
    assert_equal "光回線プラン（新）", @product.name
    assert_equal product_categories(:card), @product.product_category
  end

  test "編集時にpublishedを送信しても公開状態は変わらない" do
    sign_in @admin

    patch admin_product_path(@product), params: { product: { name: "光回線プラン", published: true, lock_version: 0 } }

    assert_not @product.reload.published?
  end

  test "無効なカテゴリに属する商材の編集画面では、現在のカテゴリを（無効）と表示し、他の無効なカテゴリは表示しない" do
    sign_in @admin
    other_inactive = ProductCategory.create!(name: "別の旧サービス", active: false)
    legacy = products(:legacy)

    get edit_admin_product_path(legacy)

    assert_response :success
    assert_select "select[name='product[product_category_id]']" do
      assert_select "option[value='#{product_categories(:inactive).id}'][selected]", text: "旧サービス（無効）"
      assert_select "option[value='#{@product_category.id}']", text: "インターネット"
      assert_select "option[value='#{other_inactive.id}']", count: 0
    end
  end

  test "無効なカテゴリに属する既存商材も、カテゴリを維持したまま編集できる" do
    sign_in @admin
    legacy = products(:legacy)

    patch admin_product_path(legacy), params: { product: { name: "旧プラン（更新）", product_category_id: product_categories(:inactive).id, lock_version: 0 } }

    assert_redirected_to admin_product_path(legacy)
    legacy.reload
    assert_equal "旧プラン（更新）", legacy.name
    assert_equal product_categories(:inactive), legacy.product_category
  end

  test "既存商材を無効なカテゴリへ変更することはできない" do
    sign_in @admin

    patch admin_product_path(@product), params: { product: { product_category_id: product_categories(:inactive).id, lock_version: 0 } }

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: "カテゴリは無効なため選択できません"
    assert_equal @product_category, @product.reload.product_category
  end

  test "lock_versionを送信しない更新は受け付けない" do
    sign_in @admin

    patch admin_product_path(@product), params: { product: { name: "改ざん" } }

    assert_response :bad_request
    assert_equal "光回線プラン", @product.reload.name
  end

  test "他の管理者が先に更新していた場合は上書きせず、日本語のエラーを表示する" do
    sign_in @admin
    @product.update!(name: "他の管理者の変更")

    patch admin_product_path(@product), params: { product: { name: "後からの変更", lock_version: 0 } }

    assert_response :conflict
    assert_select "[data-admin-form-errors] li", text: Admin::BaseController::STALE_RECORD_MESSAGE
    assert_equal "他の管理者の変更", @product.reload.name
  end

  test "公開・非公開を切り替えた後の古い編集画面からの保存は、上書きせず拒否する" do
    sign_in @admin

    patch publish_admin_product_path(@product)
    patch admin_product_path(@product), params: { product: { name: "古い画面からの変更", lock_version: 0 } }

    assert_response :conflict
    @product.reload
    assert_equal "光回線プラン", @product.name
    assert @product.published?
  end

  test "管理者は商材を公開・非公開にできる" do
    sign_in @admin

    patch publish_admin_product_path(@product)

    assert_redirected_to admin_product_path(@product)
    assert @product.reload.published?
    follow_redirect!
    assert_select ".alert", text: "商材を公開しました"
    assert_select "button", text: "非公開にする"

    patch unpublish_admin_product_path(@product)

    assert_not @product.reload.published?
  end

  test "無効なカテゴリに属する商材も公開・非公開を切り替えられる" do
    sign_in @admin
    legacy = products(:legacy)

    patch publish_admin_product_path(legacy)
    assert legacy.reload.published?

    patch unpublish_admin_product_path(legacy)
    assert_not legacy.reload.published?
  end

  test "公開・非公開の切り替えでは、他のパラメータを受け付けない" do
    sign_in @admin

    patch unpublish_admin_product_path(products(:published_card)),
          params: { published: true, name: "改ざん", product: { published: true, name: "改ざん", product_category_id: product_categories(:inactive).id } }

    product = products(:published_card).reload
    assert_not product.published?
    assert_equal "ポイントカード", product.name
    assert_equal product_categories(:card), product.product_category
  end

  test "一般ユーザーは商材管理のすべての操作で404となり、データは変わらない" do
    sign_in @user

    [ admin_products_path, new_admin_product_path, admin_product_path(@product), edit_admin_product_path(@product) ].each do |path|
      get path
      assert_response :not_found, path
    end

    assert_no_difference("Product.count") do
      post admin_products_path, params: { product: { product_category_id: @product_category.id, name: "不正な商材", summary: "概要" } }
    end
    assert_response :not_found

    patch admin_product_path(@product), params: { product: { name: "改ざん", lock_version: 0 } }
    assert_response :not_found
    patch publish_admin_product_path(@product)
    assert_response :not_found
    patch unpublish_admin_product_path(products(:published_card))
    assert_response :not_found

    assert_equal "光回線プラン", @product.reload.name
    assert_not @product.published?
    assert products(:published_card).reload.published?
  end

  test "未ログインの場合はログイン画面へリダイレクトし、データは変わらない" do
    get admin_products_path
    assert_redirected_to new_user_session_path

    assert_no_difference("Product.count") do
      post admin_products_path, params: { product: { product_category_id: @product_category.id, name: "不正な商材", summary: "概要" } }
    end
    assert_redirected_to new_user_session_path

    patch publish_admin_product_path(@product)
    assert_redirected_to new_user_session_path
    assert_not @product.reload.published?
  end
end
