require "test_helper"

# 通常録画機能の廃止と、AIロープレへの一本化を確認する（Issue #66）
#
# 通常録画の過去データはPR 2で削除するため、このテストでは画面に表示されないことと、
# AIロープレの機能・データが維持されていることを確認する。
class NormalRecordingRemovalTest < ActionDispatch::IntegrationTest
  REMOVED_ROUTES = [
    [ :post, "/practice_themes/1/create_practice" ],
    [ :get, "/analyses/1" ],
    [ :patch, "/analyses/1/smile_score" ],
    [ :delete, "/practices/1/audio" ]
  ].freeze

  REMOVED_CONSTANTS = %w[
    PracticeThemesController
    AnalysesController
    PracticeThemesHelper
    AnalysesHelper
    CreatePracticeService
    GroqTranscriptionService
    VideoAudioExtractor
    SpeechSegmentsAnalysis
  ].freeze

  REMOVED_FILES = %w[
    app/javascript/controllers/video_background_controller.js
    app/javascript/controllers/smile_analysis_controller.js
    vendor/javascript/@mediapipe--tasks-vision.js
    app/assets/images/office1.jpg
    app/assets/images/office2.jpg
    app/assets/images/simple.jpg
    app/views/practice_themes/index.html.erb
    app/views/practice_themes/show.html.erb
    app/views/analyses/show.html.erb
  ].freeze

  setup do
    @user = users(:one)
    @practice_theme = practice_themes(:one)
  end

  test "旧URLの/practice_themesはカテゴリ選択画面へ302で転送する" do
    sign_in @user

    get "/practice_themes"

    assert_response :found
    assert_redirected_to practice_categories_path
  end

  test "旧URLの/practice_themes/:idはカテゴリ選択画面へ302で転送する" do
    sign_in @user

    [ "/practice_themes/#{@practice_theme.id}", "/practice_themes/999999" ].each do |path|
      get path

      assert_response :found
      assert_redirected_to practice_categories_path
    end
  end

  test "未ログインで旧URLを開いた場合も、転送先のカテゴリ選択画面でログインを求める" do
    get "/practice_themes"
    assert_redirected_to practice_categories_path

    follow_redirect!
    assert_redirected_to new_user_session_path
  end

  test "旧AIロープレ開始URLのカテゴリ選択画面への転送は維持する" do
    sign_in @user

    assert_no_difference("AiRoleplaySession.count") do
      get ai_roleplay_practice_theme_path(@practice_theme)
    end

    assert_response :found
    assert_redirected_to practice_categories_path
  end

  test "通常録画の保存・分析結果・笑顔スコア・録音削除のルートは定義されていない" do
    REMOVED_ROUTES.each do |method, path|
      assert_raises(ActionController::RoutingError, "#{method.upcase} #{path}") do
        Rails.application.routes.recognize_path(path, method: method)
      end
    end
  end

  test "通常録画のルートヘルパーは定義されていない" do
    %i[
      practice_theme_path
      create_practice_practice_theme_path
      analysis_path
      smile_score_analysis_path
      audio_practice_path
    ].each do |helper|
      refute_respond_to Rails.application.routes.url_helpers, helper
    end
  end

  test "通常録画の新規作成POSTは404になり、PracticeもAnalysisも作成されず外部APIも呼び出さない" do
    sign_in @user
    audio = fixture_file_upload("test_volume.webm", "audio/webm")
    fail_if_called = ->(*_args, **_kwargs) { flunk "外部APIを呼び出さないこと" }

    assert_no_difference([ "Practice.count", "Analysis.count", "ActiveStorage::Blob.count" ]) do
      Net::HTTP.stub(:start, fail_if_called) do
        AiCommentService.stub(:new, fail_if_called) do
          post "/practice_themes/#{@practice_theme.id}/create_practice",
               params: { audio: audio, duration: 3.0 }
        end
      end
    end

    assert_response :not_found
  end

  test "通常録画の分析結果画面と笑顔スコア更新は404になり、分析結果は変更されない" do
    sign_in @user
    practice = Practice.create!(user: @user, practice_theme: @practice_theme)
    analysis = Analysis.create!(practice: practice, total_score: 80, smile_score: nil)

    get "/analyses/#{analysis.id}"
    assert_response :not_found

    patch "/analyses/#{analysis.id}/smile_score", params: { smile_score: 90 }
    assert_response :not_found

    analysis.reload
    assert_equal 80, analysis.total_score
    assert_nil analysis.smile_score
  end

  test "通常録画の録音削除は404になり、録音は削除されない" do
    sign_in @user
    practice = Practice.create!(user: @user, practice_theme: @practice_theme)
    practice.audio.attach(fixture_file_upload("test_volume.webm", "audio/webm"))

    delete "/practices/#{practice.id}/audio"

    assert_response :not_found
    assert practice.reload.audio.attached?
  end

  test "通常録画専用のController・Helper・Serviceは定義されていない" do
    REMOVED_CONSTANTS.each do |name|
      refute Object.const_defined?(name), "#{name}は定義されていないこと"
    end
  end

  test "通常録画専用のJavaScript・MediaPipe・背景画像・Viewは削除されている" do
    REMOVED_FILES.each do |path|
      assert_not Rails.root.join(path).exist?, "#{path}は削除されていること"
    end

    # pin_all_fromで登録したStimulus Controllerも含めて、importmapに出力される名前を確認する
    pins = JSON.parse(Rails.application.importmap.to_json(resolver: ActionController::Base.helpers))["imports"].keys
    assert_not_includes pins, "@mediapipe/tasks-vision"
    assert_not_includes pins, "controllers/video_background_controller"
    assert_not_includes pins, "controllers/smile_analysis_controller"
    assert_includes pins, "controllers/ai_roleplay_controller"
  end

  test "アプリのコードに削除したJavaScript・MediaPipe・背景画像への参照が残っていない" do
    patterns = %w[video-background video_background smile-analysis smile_analysis mediapipe office1.jpg office2.jpg simple.jpg]
    files = Dir.glob(Rails.root.join("{app,config,lib}/**/*.{rb,erb,js,css,scss,yml}").to_s)

    files.each do |file|
      content = File.read(file)

      patterns.each do |pattern|
        assert_not_includes content, pattern, "#{file.delete_prefix("#{Rails.root}/")}に#{pattern}が残っていないこと"
      end
    end
  end

  test "AIロープレの評価画面で音声分析と録画を表示し、録画を再生できる" do
    sign_in @user
    session = ai_roleplay_sessions(:one)
    practice = Practice.create!(user: @user, practice_theme: session.practice_theme, ai_roleplay_session: session)
    Analysis.create!(practice: practice, total_score: 77, speech_speed_score: 80, filler_score: 70, volume_score: 60)
    session.video.attach(io: StringIO.new("dummy video"), filename: "ai_roleplay.webm", content_type: "video/webm")

    get evaluation_ai_roleplay_path(session)

    assert_response :success
    assert_select "[data-ai-roleplay-voice-analysis-item='speech_speed'] [data-ai-roleplay-voice-analysis-score]", text: "80点"
    assert_select "[data-ai-roleplay-video] video"

    get video_ai_roleplay_path(session)

    assert_response :found
    assert_includes response.location, "ai_roleplay.webm"
  end

  test "他のユーザーのAIロープレの評価・録画は閲覧できない" do
    sign_in @user
    other_session = ai_roleplay_sessions(:two)

    get evaluation_ai_roleplay_path(other_session)
    assert_response :not_found

    # 404のレスポンスではログイン状態のCookieが更新されないため、再度ログインしてから確認する
    sign_in @user
    get video_ai_roleplay_path(other_session)
    assert_response :not_found
    assert_nil response.headers["Location"]
  end

  test "AIロープレの音声認識・音声分析の処理は維持されている" do
    %w[
      AiRoleplayTranscriptionService
      AiRoleplayVoiceAnalysisService
      AiRoleplayEvaluationService
      AiRoleplayResponseService
      PracticeAnalysisService
      VolumeAnalysis
      SpeechDurationAnalysis
      SpeechAnalysis
      ScoreAnalysis
      AiCommentService
      ClerkAudioConcatenator
      PracticeRetentionService
      AiRoleplayVideoRetentionService
    ].each do |name|
      assert Object.const_defined?(name), "#{name}は維持されていること"
    end

    assert_equal(
      { controller: "ai_roleplays", action: "transcribe" },
      Rails.application.routes.recognize_path("/ai_roleplays/transcribe", method: :post)
    )
  end

  test "PracticeTheme・Practice・Analysis・AiRoleplaySessionのモデルと関連は維持されている" do
    assert_equal :belongs_to, Practice.reflect_on_association(:practice_theme).macro
    assert_equal :belongs_to, Practice.reflect_on_association(:ai_roleplay_session).macro
    assert_equal :has_one, Practice.reflect_on_association(:analysis).macro
    assert_equal :destroy, Practice.reflect_on_association(:analysis).options[:dependent]
    assert_equal :belongs_to, Analysis.reflect_on_association(:practice).macro
    assert_equal :has_many, PracticeTheme.reflect_on_association(:practices).macro
    assert_equal :has_many, PracticeTheme.reflect_on_association(:ai_roleplay_sessions).macro
    assert_equal :has_one, AiRoleplaySession.reflect_on_association(:practice).macro
    assert Practice.new.respond_to?(:audio)
    assert Practice.new.respond_to?(:video)

    # 通常録画の過去データ（AIロープレのないPractice）は、引き続きモデルの検証を満たして保存できる
    practice = Practice.create!(user: @user, practice_theme: @practice_theme)
    assert_nil practice.ai_roleplay_session_id
    assert Analysis.create!(practice: practice, total_score: 80).persisted?
  end
end
