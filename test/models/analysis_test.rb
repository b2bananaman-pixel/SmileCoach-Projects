require "test_helper"

class AnalysisTest < ActiveSupport::TestCase
  test "声量の分析結果を保存できる" do
    practice = practices(:one)

    analysis = Analysis.create!(
      practice: practice,
      volume: -21.1
    )

    assert_equal practice, analysis.practice
    assert_in_delta(-21.1, analysis.volume, 0.01)
  end
end
