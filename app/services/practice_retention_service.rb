class PracticeRetentionService
  DEFAULT_RETENTION_DAYS = 14

  def self.delete_expired
    cutoff_time = retention_period.ago
    expired_practices = Practice.where("created_at < ?", cutoff_time)

    processed_count = 0

    expired_practices.find_each do |practice|
      next unless raw_data_present?(practice)

      practice.audio.purge if practice.audio.attached?
      practice.video.purge if practice.video.attached?
      practice.update!(transcription: nil) if practice.transcription.present?

      processed_count += 1
    end

    processed_count
  end

  def self.retention_days
    days = Integer(
      ENV.fetch(
        "PRACTICE_RETENTION_DAYS",
        DEFAULT_RETENTION_DAYS.to_s
      ),
      10
    )

    days.positive? ? days : DEFAULT_RETENTION_DAYS
  rescue ArgumentError
    DEFAULT_RETENTION_DAYS
  end

  def self.retention_period
    retention_days.days
  end

  def self.raw_data_present?(practice)
    practice.audio.attached? ||
      practice.video.attached? ||
      practice.transcription.present?
  end

  private_class_method :retention_days, :retention_period, :raw_data_present?
end
