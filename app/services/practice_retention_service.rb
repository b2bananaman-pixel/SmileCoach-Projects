class PracticeRetentionService
  RETENTION_PERIOD = 14.days

  def self.delete_expired
    cutoff_time = RETENTION_PERIOD.ago
    expired_practices = Practice.where("created_at < ?", cutoff_time)

    deleted_count = expired_practices.count

    expired_practices.find_each(&:destroy)

    deleted_count
  end
end
