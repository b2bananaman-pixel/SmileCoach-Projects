require "test_helper"

class ProductTest < ActiveSupport::TestCase
  setup do
    @product_category = product_categories(:internet)
  end

  test "必須項目だけで登録でき、新規登録時は非公開になる" do
    product = Product.create!(product_category: @product_category, name: "モバイルWi-Fi", summary: "持ち運びできるWi-Fiルーター。")

    assert_not product.published?
    assert_equal 0, product.lock_version
  end

  test "任意項目は空欄でも保存でき、空欄のメーカー・URLはnilとして保存する" do
    product = Product.create!(
      product_category: @product_category, name: "モバイルWi-Fi", summary: "持ち運びできるWi-Fiルーター。",
      maker: " ", official_url: "", features: "", pricing: "", precautions: "", proposal_points: "", confirmation_items: ""
    )

    assert_nil product.maker
    assert_nil product.official_url
  end

  test "カテゴリ・商材名・概要は必須" do
    product = Product.new(name: " ", summary: "")

    assert_not product.valid?
    assert_includes product.errors.full_messages, "カテゴリを選択してください"
    assert_includes product.errors.full_messages, "商材名を入力してください"
    assert_includes product.errors.full_messages, "概要を入力してください"
  end

  test "文字数の上限を超えると保存できない" do
    product = Product.new(
      product_category: @product_category,
      maker: "あ" * 101, name: "あ" * 101, official_url: "https://example.com/#{'a' * 481}", summary: "あ" * 1001,
      features: "あ" * 5001, pricing: "あ" * 5001, precautions: "あ" * 5001,
      proposal_points: "あ" * 5001, confirmation_items: "あ" * 5001
    )

    assert_not product.valid?
    assert_includes product.errors.full_messages, "メーカーは100文字以内で入力してください"
    assert_includes product.errors.full_messages, "商材名は100文字以内で入力してください"
    assert_includes product.errors.full_messages, "公式サイトURLは500文字以内で入力してください"
    assert_includes product.errors.full_messages, "概要は1000文字以内で入力してください"
    %w[特徴 料金・契約条件 注意事項 提案ポイント 確認すべき事項].each do |label|
      assert_includes product.errors.full_messages, "#{label}は5000文字以内で入力してください"
    end
  end

  test "文字数の上限ちょうどは保存できる" do
    product = Product.new(
      product_category: @product_category,
      maker: "あ" * 100, name: "あ" * 100, official_url: "https://example.com/#{'a' * 480}", summary: "あ" * 1000,
      features: "あ" * 5000, pricing: "あ" * 5000, precautions: "あ" * 5000,
      proposal_points: "あ" * 5000, confirmation_items: "あ" * 5000
    )

    assert product.save
  end

  test "公式サイトURLはhttp・httpsのみ許可する" do
    %w[http://example.com https://example.com/plan?id=1].each do |url|
      assert Product.new(product_category: @product_category, name: "商材", summary: "概要", official_url: url).valid?, url
    end

    [ "javascript:alert(1)", "ftp://example.com", "example.com", "https://", "https://exa mple.com", "data:text/html,x" ].each do |url|
      product = Product.new(product_category: @product_category, name: "商材", summary: "概要", official_url: url)

      assert_not product.valid?, url
      assert_includes product.errors.full_messages, "公式サイトURLはhttp://またはhttps://から始まるURLを入力してください"
    end
  end

  test "official_url_for_linkはhttp・httpsのURLだけを返し、検証を通さずに保存された不正なURLはリンクにしない" do
    product = products(:fiber)

    assert_equal "https://example.com/fiber", product.official_url_for_link

    product.update_column(:official_url, "javascript:alert(1)")
    assert_nil product.reload.official_url_for_link

    product.update_column(:official_url, nil)
    assert_nil product.reload.official_url_for_link
  end

  test "無効なカテゴリでは新規登録できない" do
    product = Product.new(product_category: product_categories(:inactive), name: "商材", summary: "概要")

    assert_not product.valid?
    assert_includes product.errors.full_messages, "カテゴリは無効なため選択できません"
  end

  test "既存商材のカテゴリを無効なカテゴリに変更できない" do
    product = products(:fiber)

    assert_not product.update(product_category: product_categories(:inactive))
    assert_includes product.errors.full_messages, "カテゴリは無効なため選択できません"
    assert_equal @product_category, product.reload.product_category
  end

  test "保存済みのカテゴリが無効になっても、他の項目を編集できる" do
    product = products(:fiber)
    @product_category.update!(active: false)

    assert product.reload.update(name: "光回線プラン（新）")
    assert_equal @product_category, product.reload.product_category
  end

  test "無効なカテゴリに属する商材も公開・非公開を切り替えられる" do
    product = products(:legacy)

    assert product.update(published: true)
    assert product.reload.published?
    assert product.update(published: false)
    assert_not product.reload.published?
  end

  test "無効なカテゴリに属する商材を有効なカテゴリへ変更できる" do
    product = products(:legacy)

    assert product.update(product_category: @product_category)
  end

  test "存在しないカテゴリはDBの外部キー制約で保存できない" do
    product = Product.new(product_category_id: 0, name: "商材", summary: "概要")

    assert_not product.valid?
    assert_raises(ActiveRecord::InvalidForeignKey) { product.save!(validate: false) }
  end

  test "published・unpublishedスコープで公開状態を絞り込める" do
    assert_includes Product.published, products(:published_card)
    assert_not_includes Product.published, products(:fiber)
    assert_includes Product.unpublished, products(:fiber)
    assert_not_includes Product.unpublished, products(:published_card)
  end

  test "同時に編集した場合、後から保存した変更は楽観的ロックで拒否される" do
    first = Product.find(products(:fiber).id)
    second = Product.find(products(:fiber).id)

    first.update!(name: "先に保存した名前")

    assert_raises(ActiveRecord::StaleObjectError) { second.update!(name: "後から保存した名前") }
    assert_equal "先に保存した名前", products(:fiber).reload.name
  end

  test "available_for_roleplayは公開中で、カテゴリが有効な商材だけを返す" do
    # 無効なカテゴリに属する公開中の商材
    products(:legacy).update!(published: true)

    products = Product.available_for_roleplay

    assert_includes products, products(:published_card)
    assert_not_includes products, products(:fiber), "非公開の商材は含めない"
    assert_not_includes products, products(:legacy), "無効なカテゴリの商材は含めない"
  end

  test "roleplay_snapshotに商材とカテゴリの情報・取得日時・形式のバージョンを含める" do
    product = products(:fiber)
    product.update!(features: "高速通信", precautions: "工事が必要", proposal_points: "在宅勤務向け", confirmation_items: "住居の種類")
    captured_at = Time.zone.parse("2026-11-08 10:00:00.123456")

    snapshot = product.roleplay_snapshot(captured_at: captured_at)

    assert_equal 1, snapshot["version"]
    assert_equal captured_at.iso8601(6), snapshot["captured_at"]
    assert_equal(
      {
        "id" => product.id, "name" => "光回線プラン", "maker" => "サンプル通信",
        "official_url" => "https://example.com/fiber", "summary" => "戸建て・マンション向けの光回線サービス。",
        "features" => "高速通信", "pricing" => "月額5,000円（2年契約）", "precautions" => "工事が必要",
        "proposal_points" => "在宅勤務向け", "confirmation_items" => "住居の種類", "lock_version" => product.lock_version
      },
      snapshot["product"]
    )
    assert_equal({ "id" => product_categories(:internet).id, "name" => "インターネット" }, snapshot["category"])
  end

  test "roleplay_snapshotはJSONに変換しても同じ内容になる" do
    snapshot = products(:fiber).roleplay_snapshot

    assert_equal snapshot, JSON.parse(snapshot.to_json)
  end

  test "AIロープレの履歴がある商材は削除できない" do
    product = products(:published_card)
    session = ai_roleplay_sessions(:one)
    session.update!(product: product, product_snapshot: product.roleplay_snapshot)

    assert_not product.destroy
    assert Product.exists?(product.id)
    assert_raises(ActiveRecord::InvalidForeignKey) { product.delete }
  end
end
