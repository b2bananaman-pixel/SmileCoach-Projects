# AIロープレ開始時点の商材情報を、終了時の保存まで保持するトークン
#
# AIロープレのセッションは終了時にまとめて保存するため、開始時点の商材情報を
# 暗号化・改ざん検知付きのトークンにして画面へ渡し、保存時に受け取って検証する。
#
# - トークンには user_id、practice_theme_id、product_id、product_snapshot を含める
# - 暗号化するため、一般ユーザーに表示していない商材情報（提案ポイントなど）をブラウザから読み取れない
# - 有効期限・用途（purpose）・ユーザー・練習テーマが一致しないトークンは受け付けない
# - 商材の存在確認は呼び出し側で行う（存在しない場合は404とするため）
class AiRoleplayProductSnapshotToken
  EXPIRES_IN = 2.hours
  PURPOSE = "ai_roleplay_product_snapshot".freeze
  KEY_SALT = "ai_roleplay_product_snapshot_token".freeze

  # 例外メッセージは固定文とし、トークンや商材情報を含めない
  class InvalidTokenError < StandardError
    def initialize(message = "商材情報のトークンが不正または期限切れです")
      super
    end
  end

  Result = Data.define(:product_id, :product_snapshot)

  class << self
    def generate(user:, practice_theme:, product:)
      encryptor.encrypt_and_sign(
        {
          "user_id" => user.id,
          "practice_theme_id" => practice_theme.id,
          "product_id" => product.id,
          "product_snapshot" => product.roleplay_snapshot
        },
        expires_in: EXPIRES_IN,
        purpose: PURPOSE
      )
    end

    # 検証できた場合は商材IDとスナップショットを返し、検証できない場合はInvalidTokenErrorを発生させる
    def verify!(token, user:, practice_theme:)
      raise InvalidTokenError unless token.is_a?(String) && token.present?

      payload = decrypt(token)

      raise InvalidTokenError unless valid_payload?(payload)
      raise InvalidTokenError unless payload["user_id"] == user.id
      raise InvalidTokenError unless payload["practice_theme_id"] == practice_theme.id

      Result.new(product_id: payload["product_id"], product_snapshot: payload["product_snapshot"])
    end

    private

    def encryptor
      key = Rails.application.key_generator.generate_key(KEY_SALT, ActiveSupport::MessageEncryptor.key_len)

      ActiveSupport::MessageEncryptor.new(key, serializer: :json)
    end

    # 改ざん・形式不正は例外、期限切れ・用途の不一致はnilになるため、どちらもnilとして扱う
    def decrypt(token)
      encryptor.decrypt_and_verify(token, purpose: PURPOSE)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature,
           ArgumentError, JSON::ParserError
      nil
    end

    def valid_payload?(payload)
      return false unless payload.is_a?(Hash)

      snapshot = payload["product_snapshot"]

      payload["user_id"].is_a?(Integer) &&
        payload["practice_theme_id"].is_a?(Integer) &&
        payload["product_id"].is_a?(Integer) &&
        snapshot.is_a?(Hash) &&
        snapshot.dig("product", "id") == payload["product_id"]
    end
  end
end
