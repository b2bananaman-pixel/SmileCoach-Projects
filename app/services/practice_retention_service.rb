class PracticeRetentionService
  RETENTION_PERIOD = 14.days

  def self.delete_expired
    cutoff_time = RETENTION_PERIOD.ago
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

  def self.raw_data_present?(practice)
    practice.audio.attached? ||
      practice.video.attached? ||
      practice.transcription.present?
  end

  private_class_method :raw_data_present?
end
