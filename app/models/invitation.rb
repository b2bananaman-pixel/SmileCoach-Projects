# 管理者が発行する新規登録の招待（Issue #90）
#
# 招待トークンは256ビットの乱数で生成し、DBにはSHA-256のダイジェストだけを保存する。
# 生のトークンは発行した直後のインスタンスでだけ参照でき（#token）、DBから読み込んだ招待からは取得できない。
# 状態は accepted_at・revoked_at・expires_at から判定する（使用済み → 取り消し済み → 期限切れ → 未使用の順）。
class Invitation < ApplicationRecord
  EXPIRES_IN = 7.days
  # SecureRandom.urlsafe_base64 に渡すバイト数（32バイト = 256ビット）
  TOKEN_BYTES = 32
  EMAIL_MAX_LENGTH = 255

  STATUS_LABELS = {
    pending: "未使用",
    accepted: "使用済み",
    revoked: "取り消し済み",
    expired: "期限切れ"
  }.freeze

  class NotRevocableError < StandardError; end
  # 登録時に、招待が使用済み・取り消し済み・期限切れになっていた場合に発生する
  class NotUsableError < StandardError; end

  belongs_to :invited_by, class_name: "User", optional: true
  belongs_to :accepted_user, class_name: "User", optional: true

  # 発行時にだけ設定する生のトークン（DBには保存しない）
  attr_reader :token

  # Deviseのメールアドレスと同じく、前後の空白を除き小文字にそろえる
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true,
                    length: { maximum: EMAIL_MAX_LENGTH },
                    format: { with: Devise.email_regexp, allow_blank: true }
  validates :token_digest, presence: true
  validates :expires_at, presence: true
  validate :email_not_registered, on: :create
  validate :no_pending_invitation_for_email, on: :create

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  # 招待を発行する（保存に失敗した場合は、エラーを持つ未保存のインスタンスを返す）
  #
  # 期限が切れた未使用の招待は、新しい招待を発行できるよう取り消し済みにする（部分一意インデックスのため）。
  def self.issue(email:, invited_by:, now: Time.current)
    invitation = new(email: email, invited_by: invited_by)
    invitation.assign_new_token(now: now)

    transaction do
      release_expired_pending(invitation.email, now: now) if invitation.email.present?
      invitation.save
      raise ActiveRecord::Rollback unless invitation.persisted?
    end

    invitation
  rescue ActiveRecord::RecordNotUnique
    # 同じメールアドレスへ同時に発行された場合は、部分一意インデックスで2件目を拒否する
    invitation.errors.add(:email, :already_invited)
    invitation
  end

  # 招待リンクのトークンから、登録に利用できる招待を探す（見つからない・利用できない場合はnil）
  #
  # トークンはダイジェストにしてから検索するため、生のトークンはDBへの問い合わせにも含まれない。
  # 配列・ハッシュなど文字列以外のパラメータは、不正なトークンとして扱う。
  def self.find_usable_by_token(token, now: Time.current)
    return unless token.is_a?(String) && token.present?

    find_by(token_digest: digest(token))&.then { |invitation| invitation if invitation.usable?(now: now) }
  end

  # セッションに保存した招待IDから、登録に利用できる招待を探す（見つからない・利用できない場合はnil）
  def self.find_usable(id, now: Time.current)
    return if id.blank?

    find_by(id: id)&.then { |invitation| invitation if invitation.usable?(now: now) }
  end

  def self.release_expired_pending(email, now:)
    where(email: email, accepted_at: nil, revoked_at: nil)
      .where(expires_at: ..now)
      .update_all(revoked_at: now, updated_at: now)
  end
  private_class_method :release_expired_pending

  def assign_new_token(now: Time.current)
    @token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    self.token_digest = self.class.digest(@token)
    self.expires_at = now + EXPIRES_IN
  end

  def status(now: Time.current)
    return :accepted if accepted_at.present?
    # 期限が切れた後に再発行のため取り消した招待は、期限切れとして表示する
    return :revoked if revoked_at.present? && revoked_at < expires_at
    return :expired if expires_at <= now
    return :revoked if revoked_at.present?

    :pending
  end

  def status_label(now: Time.current)
    STATUS_LABELS.fetch(status(now: now))
  end

  # 未使用・未取り消し・期限内の場合だけ、登録に利用できる
  def usable?(now: Time.current)
    status(now: now) == :pending
  end

  # 未使用・未取り消し・期限内の招待だけを取り消す（他の管理者の操作と重ならないよう行をロックして確認する）
  def revoke!(now: Time.current)
    with_lock do
      raise NotRevocableError unless usable?(now: now)

      update!(revoked_at: now)
    end
  end

  # 招待を使ってユーザーを登録する（登録できた場合はtrue、ユーザーの入力に誤りがある場合はfalse）
  #
  # 同時に同じ招待で登録されても1件だけ成功するよう、招待の行をロックしてから有効性を確かめ、
  # ユーザーの作成と招待の使用済み化を同じトランザクションで行う。
  # ユーザーを保存できなかった場合はロールバックし、招待は未使用のまま残す（エラーはuserに入る）。
  # メールアドレスは送信された値を使わず、招待先のメールアドレスにする。
  # 招待が使用済み・取り消し済み・期限切れになっていた場合は NotUsableError を発生させる。
  def accept_with(user, now: Time.current)
    accepted = false

    transaction do
      lock!
      raise NotUsableError unless usable?(now: now)

      user.email = email
      raise ActiveRecord::Rollback unless user.save

      update!(accepted_at: now, accepted_user: user)
      accepted = true
    end

    accepted
  rescue ActiveRecord::RecordNotUnique
    # 同じメールアドレスのユーザーが同時に作成された場合（usersのemailの一意インデックス）
    user.errors.add(:email, :taken)
    false
  end

  private

  def email_not_registered
    return if email.blank?
    return unless User.exists?(email: email)

    errors.add(:email, :already_registered)
  end

  def no_pending_invitation_for_email
    return if email.blank?

    pending = self.class.where(email: email, accepted_at: nil, revoked_at: nil)
    pending = pending.where.not(id: id) if persisted?
    errors.add(:email, :already_invited) if pending.exists?
  end
end
