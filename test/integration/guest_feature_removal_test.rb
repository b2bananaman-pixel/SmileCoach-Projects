require "test_helper"

# ゲスト録音分析機能の廃止を確認する（Issue #87）
#
# ゲスト用の画面・APIはログイン不要でGroq APIを呼び出していたため、ルートごと廃止した。
class GuestFeatureRemovalTest < ActionDispatch::IntegrationTest
  GUEST_PATHS = [
    [ :get, "/guest/practice_themes" ],
    [ :get, "/guest/practice_themes/1" ],
    [ :post, "/guest/practice_themes/1/create_practice" ]
  ].freeze

  setup do
    @practice_theme = practice_themes(:one)
  end

  test "ゲスト用のルートは定義されていない" do
    GUEST_PATHS.each do |method, path|
      assert_raises(ActionController::RoutingError, "#{method.upcase} #{path}") do
        Rails.application.routes.recognize_path(path, method: method)
      end
    end
  end

  test "ゲスト用のルートヘルパーは定義されていない" do
    %i[guest_practice_themes_path guest_practice_theme_path create_guest_practice_path].each do |helper|
      refute_respond_to Rails.application.routes.url_helpers, helper
    end
  end

  test "ゲスト専用のControllerとServiceは定義されていない" do
    %w[
      GuestPracticeThemesController
      GuestAudioAnalysisService
      GuestAnalysisResult
      GuestVolumeAnalysis
      GuestSpeechDurationAnalysis
      GuestTranscriptionService
    ].each do |name|
      refute Object.const_defined?(name), "#{name}は定義されていないこと"
    end
  end

  test "未ログインユーザーがゲスト用の画面を開くと404になる" do
    get "/guest/practice_themes"
    assert_response :not_found

    get "/guest/practice_themes/#{@practice_theme.id}"
    assert_response :not_found
  end

  test "未ログインユーザーがゲスト録音分析APIを呼び出すと404になり、Groq APIを呼び出さない" do
    audio = fixture_file_upload("test_audio.webm", "audio/webm")
    fail_if_called = ->(*_args, **_kwargs) { flunk "Groq APIを呼び出さないこと" }

    assert_no_difference([ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count" ]) do
      Net::HTTP.stub(:start, fail_if_called) do
        AiRoleplayTranscriptionService.stub(:new, fail_if_called) do
          GroqTranscriptionService.stub(:new, fail_if_called) do
            AiCommentService.stub(:new, fail_if_called) do
              post "/guest/practice_themes/#{@practice_theme.id}/create_practice",
                   params: { audio: audio, duration: 3.0 }
            end
          end
        end
      end
    end

    assert_response :not_found
  end

  test "ログイン済みのユーザーでもゲスト録音分析APIは404になる" do
    sign_in users(:one)

    post "/guest/practice_themes/#{@practice_theme.id}/create_practice",
         params: { audio: fixture_file_upload("test_audio.webm", "audio/webm"), duration: 3.0 }

    assert_response :not_found
  end
end
