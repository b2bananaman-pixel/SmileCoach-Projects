require "test_helper"

class AiRoleplayProductSnapshotTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @practice_theme = practice_themes(:one)
    @product = products(:published_card)
  end

  test "生成したトークンから商材IDと開始時点のスナップショットを取得できる" do
    token = generate_token

    result = AiRoleplayProductSnapshotToken.verify!(token, user: @user, practice_theme: @practice_theme)

    assert_equal @product.id, result.product_id
    assert_equal "ポイントカード", result.product_snapshot.dig("product", "name")
    assert_equal "カード", result.product_snapshot.dig("category", "name")
    assert_equal Product::ROLEPLAY_SNAPSHOT_VERSION, result.product_snapshot["version"]
  end

  test "トークン生成後に商材を編集しても、トークンのスナップショットは生成時点の内容のまま" do
    token = generate_token
    @product.update!(name: "編集後の名前", summary: "編集後の概要")

    result = AiRoleplayProductSnapshotToken.verify!(token, user: @user, practice_theme: @practice_theme)

    assert_equal "ポイントカード", result.product_snapshot.dig("product", "name")
    assert_equal "買い物でポイントが貯まるクレジットカード。", result.product_snapshot.dig("product", "summary")
  end

  test "トークンは暗号化され、商材情報を読み取れない" do
    @product.update!(proposal_points: "提案ポイントの社内情報")
    token = generate_token

    decoded = token.split("--").map { |part| Base64.decode64(part).force_encoding(Encoding::UTF_8) }.join

    [ "ポイントカード", "提案ポイントの社内情報", "product_snapshot" ].each do |text|
      assert_not_includes token, text
      assert_not_includes decoded, text
    end
  end

  test "改ざんされたトークンは拒否する" do
    token = generate_token
    tampered = token.dup
    tampered[10] = tampered[10] == "A" ? "B" : "A"

    assert_invalid_token(tampered)
  end

  test "形式が不正なトークンは拒否する" do
    [ nil, "", "abc", "a--b--c", "--", [ generate_token ], { "token" => generate_token } ].each do |token|
      assert_invalid_token(token)
    end
  end

  test "有効期限（2時間）を過ぎたトークンは拒否する" do
    token = generate_token

    travel 2.hours - 1.minute do
      assert AiRoleplayProductSnapshotToken.verify!(token, user: @user, practice_theme: @practice_theme)
    end

    travel 2.hours + 1.second do
      assert_invalid_token(token)
    end
  end

  test "別のユーザーのトークンは拒否する" do
    token = generate_token

    assert_raises(AiRoleplayProductSnapshotToken::InvalidTokenError) do
      AiRoleplayProductSnapshotToken.verify!(token, user: users(:two), practice_theme: @practice_theme)
    end
  end

  test "別の練習テーマのトークンは拒否する" do
    token = generate_token

    assert_raises(AiRoleplayProductSnapshotToken::InvalidTokenError) do
      AiRoleplayProductSnapshotToken.verify!(token, user: @user, practice_theme: practice_themes(:two))
    end
  end

  test "別の用途で暗号化したデータはトークンとして受け付けない" do
    key = Rails.application.key_generator.generate_key(
      AiRoleplayProductSnapshotToken::KEY_SALT, ActiveSupport::MessageEncryptor.key_len
    )
    token = ActiveSupport::MessageEncryptor.new(key, serializer: :json).encrypt_and_sign(
      { "user_id" => @user.id, "practice_theme_id" => @practice_theme.id, "product_id" => @product.id,
        "product_snapshot" => @product.roleplay_snapshot },
      purpose: "other_purpose"
    )

    assert_invalid_token(token)
  end

  test "エラーメッセージにトークンや商材情報を含めない" do
    token = generate_token

    error = assert_raises(AiRoleplayProductSnapshotToken::InvalidTokenError) do
      AiRoleplayProductSnapshotToken.verify!(token, user: users(:two), practice_theme: @practice_theme)
    end

    assert_equal "商材情報のトークンが不正または期限切れです", error.message
  end

  private

  def generate_token
    AiRoleplayProductSnapshotToken.generate(user: @user, practice_theme: @practice_theme, product: @product)
  end

  def assert_invalid_token(token)
    assert_raises(AiRoleplayProductSnapshotToken::InvalidTokenError) do
      AiRoleplayProductSnapshotToken.verify!(token, user: @user, practice_theme: @practice_theme)
    end
  end
end
