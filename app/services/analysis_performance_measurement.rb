module AnalysisPerformanceMeasurement
  private

  def measure(label)
    started_at = monotonic_time
    result = yield

    log_duration(
      label,
      monotonic_time - started_at
    )

    result
  end

  def log_duration(label, seconds)
    Rails.logger.info(
      "[AnalysisPerformance] #{label}: #{format('%.2f', seconds)}秒"
    )
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
