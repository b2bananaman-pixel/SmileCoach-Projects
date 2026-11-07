class User < ApplicationRecord
  # 旧adminカラムは、旧コードに戻した場合の互換性のためにDBに残し、権限の判定にはroleを使う
  # 新コードから読み書きするとenumのadmin?と名前が重なり意味を取り違えるため、モデルからは無視する
  self.ignored_columns += [ "admin" ]

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # 値を変更すると既存ユーザーの権限が変わるため、数値を明示する（DBのCHECK制約と合わせる）
  enum :role, { user: 0, admin: 1, super_admin: 2 }, default: :user, validate: true

  LAST_SUPER_ADMIN_ERROR_MESSAGE = "最後の最高管理者の権限は変更・削除できません".freeze

  validates :name, presence: true

  # 最後の最高管理者を降格・解除・削除できないようにする
  before_update :ensure_super_admin_remains, if: -> { will_save_change_to_role? && !super_admin? }
  before_destroy :ensure_super_admin_remains, prepend: true

  has_many :practices
  has_many :ai_roleplay_sessions, dependent: :destroy

  # 最高管理者の行をID順にロックし、トランザクション終了まで他の権限変更・削除を待たせる
  def self.lock_super_admin_ids
    super_admin.order(:id).lock.pluck(:id)
  end

  # 管理者向け機能を利用できる権限（最高管理者は管理者の機能もすべて利用できる）
  def admin_access?
    admin? || super_admin?
  end

  # 権限を変更し、旧adminカラムも同じトランザクションで同期する
  #
  # 旧コードに戻した場合も同じユーザーが管理画面を使えるよう、旧adminカラムにはadmin_access?の結果を書き込む。
  # デッドロックを避けるため、最高管理者の行を先にID順でロックしてから、対象ユーザーをロックする。
  def change_role!(new_role)
    transaction do
      self.class.lock_super_admin_ids
      lock!

      update!(role: new_role)
      self.class.where(id: id).update_all(admin: admin_access?)
    end
  end

  private

  # ロックした時点のDBの状態で、このユーザーが唯一の最高管理者かを確認する
  # （メモリ上のroleが古い場合でも、DBの値で判定する）
  def ensure_super_admin_remains
    return unless self.class.lock_super_admin_ids == [ id ]

    errors.add(:base, LAST_SUPER_ADMIN_ERROR_MESSAGE)
    throw :abort
  end
end
