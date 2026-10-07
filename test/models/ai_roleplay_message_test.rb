require "test_helper"

class AiRoleplayMessageTest < ActiveSupport::TestCase
  test "is valid with user role and content" do
    message = AiRoleplayMessage.new(
      ai_roleplay_session: ai_roleplay_sessions(:one),
      role: "user",
      content: "現在インターネットは何をご利用ですか？"
    )

    assert message.valid?
  end

  test "is valid with assistant role and content" do
    message = AiRoleplayMessage.new(
      ai_roleplay_session: ai_roleplay_sessions(:one),
      role: "assistant",
      content: "今は他社の光回線を使っています。"
    )

    assert message.valid?
  end

  test "is invalid without role" do
    message = AiRoleplayMessage.new(
      ai_roleplay_session: ai_roleplay_sessions(:one),
      role: nil,
      content: "テスト発話"
    )

    assert_not message.valid?
    assert message.errors.of_kind?(:role, :blank)
  end

  test "is invalid with unsupported role" do
    message = AiRoleplayMessage.new(
      ai_roleplay_session: ai_roleplay_sessions(:one),
      role: "system",
      content: "テスト発話"
    )

    assert_not message.valid?
    assert message.errors.of_kind?(:role, :inclusion)
  end

  test "is invalid without content" do
    message = AiRoleplayMessage.new(
      ai_roleplay_session: ai_roleplay_sessions(:one),
      role: "user",
      content: nil
    )

    assert_not message.valid?
    assert message.errors.of_kind?(:content, :blank)
  end
end
