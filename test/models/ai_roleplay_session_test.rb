require "test_helper"

class AiRoleplaySessionTest < ActiveSupport::TestCase
  test "belongs to user" do
    session = ai_roleplay_sessions(:one)

    assert_equal users(:one), session.user
  end

  test "belongs to practice theme" do
    session = ai_roleplay_sessions(:one)

    assert_equal practice_themes(:one), session.practice_theme
  end

  test "has many ai roleplay messages" do
    session = ai_roleplay_sessions(:one)

    assert_equal 2, session.ai_roleplay_messages.count
  end

  test "destroys associated messages when destroyed" do
    session = ai_roleplay_sessions(:one)

    assert_difference("AiRoleplayMessage.count", -2) do
      session.destroy
    end
  end

  test "has one ai roleplay evaluation" do
    session = ai_roleplay_sessions(:one)

    assert_equal ai_roleplay_evaluations(:one),
                 session.ai_roleplay_evaluation
  end

  test "destroys associated evaluation when destroyed" do
    session = ai_roleplay_sessions(:one)

    assert_difference("AiRoleplayEvaluation.count", -1) do
      session.destroy!
    end
  end

  test "音声分析用のPracticeがない場合はpracticeがnilになる" do
    session = ai_roleplay_sessions(:one)

    assert_nil session.practice
  end

  test "削除時に音声分析用のPracticeとAnalysisも削除する" do
    session = ai_roleplay_sessions(:one)

    practice = Practice.create!(
      user: session.user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    practice.create_analysis!(
      speech_speed: 5.5,
      speech_speed_score: 100,
      filler_count: 0,
      filler_score: 100,
      volume: -15.0,
      volume_score: 100,
      total_score: 100
    )

    assert_difference(
      [ "Practice.count", "Analysis.count" ],
      -1
    ) do
      session.destroy!
    end
  end

  test "削除時に通常録画のPracticeは削除しない" do
    session = ai_roleplay_sessions(:one)

    assert_no_difference("Practice.count") do
      session.destroy!
    end

    assert Practice.exists?(practices(:one).id)
  end

  test "ユーザーのAIロープレを一括削除すると音声分析用Practiceも削除される" do
    session = ai_roleplay_sessions(:two)
    user = session.user

    Practice.create!(
      user: user,
      practice_theme: session.practice_theme,
      ai_roleplay_session: session
    )

    # 音声分析用Practiceが先に削除され、外部キー違反にならないこと
    assert_difference("AiRoleplaySession.count", -1) do
      user.ai_roleplay_sessions.destroy_all
    end

    assert_not Practice.exists?(ai_roleplay_session_id: session.id)
  end

  test "商材を指定しないセッションはproduct・product_snapshotがnilのまま保存できる" do
    session = ai_roleplay_sessions(:one)

    assert_nil session.product
    assert_nil session.product_snapshot
    assert session.update(duration: 60.0)
  end

  test "商材と開始時点のスナップショットを保存できる" do
    session = ai_roleplay_sessions(:one)
    product = products(:published_card)
    snapshot = product.roleplay_snapshot

    session.update!(product: product, product_snapshot: snapshot)
    session.reload

    assert_equal product, session.product
    assert_equal snapshot, session.product_snapshot
    assert_includes product.ai_roleplay_sessions, session
  end

  test "商材IDとスナップショットの片方だけを保存することはDBの制約で防ぐ" do
    session = ai_roleplay_sessions(:one)
    product = products(:published_card)

    assert_raises(ActiveRecord::StatementInvalid) do
      AiRoleplaySession.transaction(requires_new: true) { session.update_columns(product_id: product.id) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      AiRoleplaySession.transaction(requires_new: true) { session.update_columns(product_snapshot: product.roleplay_snapshot) }
    end
    assert_nil session.reload.product_id
  end

  test "スナップショットはJSONのオブジェクト以外を保存できない" do
    session = ai_roleplay_sessions(:one)

    assert_raises(ActiveRecord::StatementInvalid) do
      session.update_columns(product_id: products(:published_card).id, product_snapshot: [ "配列" ])
    end
  end

  test "存在しない商材IDはDBの外部キー制約で保存できない" do
    session = ai_roleplay_sessions(:one)

    assert_raises(ActiveRecord::InvalidForeignKey) do
      session.update_columns(product_id: 0, product_snapshot: { "version" => 1 })
    end
  end

  test "商材を起点としたセッションは練習テーマなしで保存できる" do
    product = products(:published_card)
    session = AiRoleplaySession.create!(user: users(:one), product: product, product_snapshot: product.roleplay_snapshot)

    assert_nil session.reload.practice_theme
    assert_equal product, session.product
  end

  test "練習テーマも商材もないセッションは保存できない" do
    session = AiRoleplaySession.new(user: users(:one))

    assert_not session.valid?
    assert_includes session.errors[:base], "練習テーマまたは商材を指定してください"
  end

  test "練習テーマも商材もないセッションはDBのチェック制約でも保存できない" do
    session = AiRoleplaySession.new(user: users(:one))

    assert_raises(ActiveRecord::StatementInvalid) { session.save!(validate: false) }
  end

  test "表示名は商材がある場合はカテゴリ名・商材名、商材のない過去のセッションは練習テーマ名とする" do
    product = products(:published_card)
    product_session = AiRoleplaySession.new(product: product, product_snapshot: product.roleplay_snapshot)
    legacy_session = AiRoleplaySession.new(practice_theme: practice_themes(:one))

    assert_equal "カード", product_session.roleplay_category_name
    assert_equal "ポイントカード", product_session.roleplay_product_name
    assert_equal "カード／ポイントカード", product_session.roleplay_title

    assert_nil legacy_session.roleplay_category_name
    assert_nil legacy_session.roleplay_product_name
    assert_equal practice_themes(:one).name, legacy_session.roleplay_title
  end

  test "表示名は練習開始時点の商材情報を使い、商材の編集後も変わらない" do
    product = products(:published_card)
    session = AiRoleplaySession.create!(user: users(:one), product: product, product_snapshot: product.roleplay_snapshot)

    product.update!(name: "編集後の名前")

    assert_equal "カード／ポイントカード", session.reload.roleplay_title
  end

  test "スナップショットの形式が不正でも表示名でエラーにならない" do
    session = AiRoleplaySession.new(practice_theme: practice_themes(:one),
                                    product_snapshot: { "product" => { "name" => 123 } })

    assert_nil session.roleplay_product_name
    assert_equal practice_themes(:one).name, session.roleplay_title
    assert_equal AiRoleplaySession::NO_PRODUCT_LABEL, AiRoleplaySession.new.roleplay_title
  end
end
