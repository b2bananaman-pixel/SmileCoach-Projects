require "test_helper"

class Admin::ProductCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @super_admin = users(:super_admin)
    @user = users(:two)
    @product_category = product_categories(:internet)
  end

  test "カテゴリ管理のルーティングに削除と詳細はない" do
    assert_equal "/admin/product_categories", admin_product_categories_path
    assert_recognizes({ controller: "admin/product_categories", action: "activate", id: "1" },
                      { path: "/admin/product_categories/1/activate", method: :patch })
    assert_recognizes({ controller: "admin/product_categories", action: "deactivate", id: "1" },
                      { path: "/admin/product_categories/1/deactivate", method: :patch })

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/admin/product_categories/1", method: :delete)
    end
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/admin/product_categories/1", method: :get)
    end
  end

  test "管理者はカテゴリ一覧で状態と商材の件数を確認できる" do
    sign_in @admin

    get admin_product_categories_path

    assert_response :success
    assert_select "title", text: "カテゴリ管理"
    assert_select "tr[data-product-category-id='#{@product_category.id}']" do
      assert_select "td", text: "インターネット"
      assert_select ".badge", text: "有効"
      assert_select "[data-product-count]", text: "1件"
      assert_select "button", text: "無効にする"
    end
    assert_select "tr[data-product-category-id='#{product_categories(:inactive).id}']" do
      assert_select ".badge", text: "無効"
      assert_select "button", text: "有効にする"
    end
  end

  test "最高管理者もカテゴリを管理できる" do
    sign_in @super_admin

    get admin_product_categories_path
    assert_response :success

    assert_difference("ProductCategory.count", 1) do
      post admin_product_categories_path, params: { product_category: { name: "ネットテレビ" } }
    end
  end

  test "管理者はカテゴリを登録でき、初期状態は有効になる" do
    sign_in @admin

    get new_admin_product_category_path
    assert_response :success

    assert_difference("ProductCategory.count", 1) do
      post admin_product_categories_path, params: { product_category: { name: "  ネットテレビ　" } }
    end

    product_category = ProductCategory.last
    assert_equal "ネットテレビ", product_category.name
    assert product_category.active?
    assert_redirected_to admin_product_categories_path
    follow_redirect!
    assert_select ".alert", text: "カテゴリを登録しました"
  end

  test "登録時にactiveを送信しても無視され、有効なカテゴリとして登録される" do
    sign_in @admin

    post admin_product_categories_path, params: { product_category: { name: "ネットテレビ", active: false, lock_version: 5 } }

    product_category = ProductCategory.last
    assert product_category.active?
    assert_equal 0, product_category.lock_version
  end

  test "カテゴリ名が空欄・重複の場合は登録できず、日本語のエラーを表示する" do
    sign_in @admin

    assert_no_difference("ProductCategory.count") do
      post admin_product_categories_path, params: { product_category: { name: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: "カテゴリ名を入力してください"

    assert_no_difference("ProductCategory.count") do
      post admin_product_categories_path, params: { product_category: { name: "ｲﾝﾀｰﾈｯﾄ" } }
    end
    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: "カテゴリ名はすでに使用されています"
  end

  test "同時登録でDBの一意制約に違反した場合も、重複のエラーを表示する" do
    sign_in @admin

    # 重複の確認（バリデーション）を通過した後に、別の管理者が同じ名前を登録していた状況を再現する
    original_new = ProductCategory.method(:new)
    skip_validation_new = lambda do |*args|
      original_new.call(*args).tap { |record| record.define_singleton_method(:valid?) { |*| true } }
    end

    ProductCategory.stub(:new, skip_validation_new) do
      assert_no_difference("ProductCategory.count") do
        post admin_product_categories_path, params: { product_category: { name: "インターネット" } }
      end
    end

    assert_response :unprocessable_entity
    assert_select "[data-admin-form-errors] li", text: "カテゴリ名はすでに使用されています"
  end

  test "管理者はカテゴリ名を編集できる" do
    sign_in @admin

    get edit_admin_product_category_path(@product_category)
    assert_response :success
    assert_select "input[name='product_category[lock_version]'][value='0']"

    patch admin_product_category_path(@product_category), params: { product_category: { name: "光回線", lock_version: 0 } }

    assert_redirected_to admin_product_categories_path
    assert_equal "光回線", @product_category.reload.name
  end

  test "編集時にactiveを送信しても状態は変わらない" do
    sign_in @admin

    patch admin_product_category_path(@product_category), params: { product_category: { name: "光回線", active: false, lock_version: 0 } }

    assert @product_category.reload.active?
  end

  test "lock_versionを送信しない更新は受け付けない" do
    sign_in @admin

    patch admin_product_category_path(@product_category), params: { product_category: { name: "光回線" } }

    assert_response :bad_request
    assert_equal "インターネット", @product_category.reload.name
  end

  test "他の管理者が先に更新していた場合は上書きせず、日本語のエラーを表示する" do
    sign_in @admin
    @product_category.update!(name: "他の管理者の変更")

    patch admin_product_category_path(@product_category), params: { product_category: { name: "後からの変更", lock_version: 0 } }

    assert_response :conflict
    assert_select "[data-admin-form-errors] li", text: Admin::BaseController::STALE_RECORD_MESSAGE
    assert_equal "他の管理者の変更", @product_category.reload.name
  end

  test "管理者はカテゴリを無効化・有効化でき、既存商材の関連付けは維持される" do
    sign_in @admin

    patch deactivate_admin_product_category_path(@product_category)

    assert_redirected_to admin_product_categories_path
    assert_not @product_category.reload.active?
    assert_equal @product_category, products(:fiber).reload.product_category

    patch activate_admin_product_category_path(@product_category)

    assert @product_category.reload.active?
  end

  test "有効・無効の切り替えでは、名前などのパラメータを受け付けない" do
    sign_in @admin

    patch deactivate_admin_product_category_path(@product_category),
          params: { active: true, name: "改ざん", product_category: { active: true, name: "改ざん" } }

    @product_category.reload
    assert_not @product_category.active?
    assert_equal "インターネット", @product_category.name
  end

  test "一般ユーザーはカテゴリ管理のすべての操作で404となり、データは変わらない" do
    sign_in @user

    get admin_product_categories_path
    assert_response :not_found
    get new_admin_product_category_path
    assert_response :not_found
    get edit_admin_product_category_path(@product_category)
    assert_response :not_found

    assert_no_difference("ProductCategory.count") do
      post admin_product_categories_path, params: { product_category: { name: "不正なカテゴリ" } }
    end
    assert_response :not_found

    patch admin_product_category_path(@product_category), params: { product_category: { name: "改ざん", lock_version: 0 } }
    assert_response :not_found
    patch deactivate_admin_product_category_path(@product_category)
    assert_response :not_found
    patch activate_admin_product_category_path(product_categories(:inactive))
    assert_response :not_found

    assert_equal "インターネット", @product_category.reload.name
    assert @product_category.active?
    assert_not product_categories(:inactive).reload.active?
  end

  test "未ログインの場合はログイン画面へリダイレクトし、データは変わらない" do
    get admin_product_categories_path
    assert_redirected_to new_user_session_path

    assert_no_difference("ProductCategory.count") do
      post admin_product_categories_path, params: { product_category: { name: "不正なカテゴリ" } }
    end
    assert_redirected_to new_user_session_path

    patch deactivate_admin_product_category_path(@product_category)
    assert_redirected_to new_user_session_path
    assert @product_category.reload.active?
  end
end
