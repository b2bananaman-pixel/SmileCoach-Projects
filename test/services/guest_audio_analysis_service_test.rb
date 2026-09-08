require "test_helper"

class GuestAudioAnalysisServiceTest < ActiveSupport::TestCase
  test "音声を分析してゲスト用の分析結果を返す" do
    audio = StringIO.new("dummy audio")

    speech_analysis = Minitest::Mock.new
    speech_analysis.expect(:speech_speed, 5.5)
    speech_analysis.expect(:filler_score, 80)
    speech_analysis.expect(:filler_count, 2)
    speech_analysis.expect(:speech_speed, 5.5)
    speech_analysis.expect(:filler_score, 80)

    score_analysis = Minitest::Mock.new
    score_analysis.expect(:total_score, 85)
    score_analysis.expect(:speech_speed_score, 100)
    score_analysis.expect(:volume_score, 70)

    GuestTranscriptionService.stub(
      :new,
      ->(_audio_file) {
        service = Minitest::Mock.new
        service.expect(:call, "こんにちは今日はいい天気ですね")
        service
      }
    ) do
      GuestVolumeAnalysis.stub(
        :new,
        ->(_audio_file) {
          service = Minitest::Mock.new
          service.expect(:volume, -18.0)
          service
        }
      ) do
        GuestSpeechDurationAnalysis.stub(
          :new,
          ->(_audio_file, duration:) {
            assert_equal 10.0, duration
            service = Minitest::Mock.new
            service.expect(:speech_duration, 8.0)
            service
          }
        ) do
          SpeechAnalysis.stub(:new, speech_analysis) do
            ScoreAnalysis.stub(:new, score_analysis) do
              AiCommentService.stub(
                :new,
                ->(result) {
                  assert_equal 85, result.total_score

                  service = Minitest::Mock.new
                  service.expect(
                    :call,
                    "次回は話す速さを意識しましょう。"
                  )
                  service
                }
              ) do
                result = GuestAudioAnalysisService.new(
                  audio: audio,
                  duration: 10.0
                ).call

                assert_instance_of GuestAnalysisResult, result
                assert_equal 85, result.total_score
                assert_equal 5.5, result.speech_speed
                assert_equal 100, result.speech_speed_score
                assert_equal 2, result.filler_count
                assert_equal 80, result.filler_score
                assert_equal(-18.0, result.volume)
                assert_equal 70, result.volume_score
                assert_equal(
                  "次回は話す速さを意識しましょう。",
                  result.ai_comment
                )
              end
            end
          end
        end
      end
    end

    speech_analysis.verify
    score_analysis.verify
  end
end
