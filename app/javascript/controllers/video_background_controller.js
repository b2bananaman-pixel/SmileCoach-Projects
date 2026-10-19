import { Controller } from "@hotwired/stimulus";
import {
  ImageSegmenter,
  FilesetResolver
} from "@mediapipe/tasks-vision";

/*
 * 推論に失敗したときに
 * 前回の人物画像を使い続ける最大時間（ミリ秒）。
 */
const MASK_HOLD_MS = 500;

/*
 * requestVideoFrameCallbackの通知が
 * この時間（ミリ秒）届かない場合は、
 * 通知が停止したとみなし、
 * video.currentTimeでフレーム判定を行う。
 *
 * フレーム検出が動作しない環境でも
 * 人物が静止したままにならないようにする。
 */
const FRAME_STALE_MS = 100;

/*
 * 人物マスクの調整値
 *
 * MASK_ALPHA_LOW:
 *   人物の確信度がこの値以下なら背景（完全に透明）。
 *   上げると周囲に残る元の背景が減り、
 *   下げると人物が欠けにくくなる。
 *
 * MASK_ALPHA_HIGH:
 *   人物の確信度がこの値以上なら人物（完全に不透明）。
 *   下げると顔や服が透けにくくなる。
 *
 * LOWとHIGHの間だけを輪郭として滑らかに透過させる。
 */
const MASK_ALPHA_LOW = 0.50;
const MASK_ALPHA_HIGH = 0.80;

/*
 * フレーム間の平滑化で前フレームの値を残す割合（0〜1）。
 *
 * 確信度が上がる場合も下がる場合も同じ割合で平滑化し、
 * 静止時の輪郭のちらつきを抑える。
 * 値を大きくするほどちらつきは減るが、動きへの追従が遅くなる。
 */
const MASK_SMOOTHING_WEIGHT = 0.5;

/*
 * 前フレームとの確信度の差がこの値を超えた場合は、
 * 平滑化せず現在のフレームの値をすぐに反映する。
 *
 * 人物が動いたときの追従性を保ち、
 * 画面外へ出たときに残像が残らないようにする。
 */
const MASK_MOTION_DIFF = 0.4;

/*
 * 輪郭をぼかす強さ（px）。0でぼかしなし。
 *
 * ぼかすのはマスクの透明度だけで、
 * 顔や服の映像そのものはぼかさない。
 */
const MASK_EDGE_BLUR_PX = 0.5;

/*
 * 人物認識モデル
 *
 * landscape: selfie_segmenter_landscape（入力256×144）
 * square:    selfie_segmenter（入力256×256）
 *
 * 通常利用時は既定のlandscapeを使用する。
 * squareは ?vb_debug=1&vb_model=square の場合だけ使用する。
 */
const SEGMENTATION_MODELS = {
  landscape:
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter_landscape/float16/1/selfie_segmenter_landscape.tflite",
  square:
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite"
};

const DEFAULT_SEGMENTATION_MODEL = "landscape";

/*
 * デバッグモード（?vb_debug=1）用の設定
 */
const DEBUG_VIEWS = [
  "confidence",
  "alpha",
  "edge"
];

const DEBUG_MAX_EDGE_BLUR_PX = 4;

/*
 * 処理時間とマスク統計をConsoleへ出す間隔（ミリ秒）
 */
const DEBUG_REPORT_INTERVAL_MS = 2000;

/*
 * 推論用画像の幅（?vb_debug=1&vb_input=320）の範囲
 *
 * 高さはカメラ映像のアスペクト比から決める。
 */
const DEBUG_MIN_INPUT_WIDTH = 64;
const DEBUG_MAX_INPUT_WIDTH = 1920;

/*
 * 推論の実行方法（?vb_debug=1&vb_delegate=gpu）
 *
 * 通常利用時は常にCPU。
 */
const DEFAULT_SEGMENTATION_DELEGATE = "CPU";
const DEBUG_DELEGATES = {
  cpu: "CPU",
  gpu: "GPU"
};

export default class extends Controller {
  static targets = [
    "sourceVideo",
    "preview",
    "startButton",
    "stopButton",
    "backgroundButton",
    "status"
  ];

  static values = {
    createUrl: String
  };

  connect() {
    this.selectedBackground = null;
    this.backgroundImage = null;

    this.mediaStream = null;
    this.recordingStream = null;
    this.mediaRecorder = null;
    this.recordedChunks = [];

    /*
     * AIロープレ録音用 Audio Mixer
     *
     * 店員のマイク音声とAI顧客のTTS音声を
     * Web Audio APIで1本の音声トラックにまとめる。
     */
    this.audioContext = null;
    this.microphoneSource = null;
    this.recordingDestination = null;

    /*
     * AI顧客のTTS音声を受け取るための
     * カスタムイベント。
     */
    this.handleAiAudio =
      this.handleAiAudio.bind(this);

    window.addEventListener(
      "ai-roleplay:play-audio",
      this.handleAiAudio
    );

    this.segmenter = null;
    this.segmenterDelegate = null;
    this.isProcessing = false;

    /*
     * ImageSegmenterの読み込みに失敗した場合はtrue。
     *
     * バーチャル背景なしで録画できるようにする。
     */
    this.segmenterFailed = false;

    /*
     * disconnect後に非同期処理が完了した場合の
     * リソース解放判定に使用する。
     */
    this.isDisconnected = false;

    /*
     * 前回のマスク
     *
     * 動きが少ないときのちらつきを
     * 抑えるために使用する。
     */
    this.previousStableMask = null;

    /*
     * 再利用するCanvas
     *
     * frameCanvas:
     *   推論と切り抜きに使う
     *   カメラ映像の1フレーム。
     *
     * personCanvas:
     *   frameCanvasと同じフレームから
     *   切り抜いた人物画像。
     *   次の推論成功まで再利用する。
     */
    this.frameCanvas =
      document.createElement("canvas");

    this.frameContext =
      this.frameCanvas.getContext("2d");

    this.personCanvas =
      document.createElement("canvas");

    this.personContext =
      this.personCanvas.getContext("2d");

    this.maskCanvas =
      document.createElement("canvas");

    this.maskContext =
      this.maskCanvas.getContext("2d");

    this.maskImageData = null;
    this.refinedMaskBuffer = null;

    /*
     * フレーム管理
     *
     * requestVideoFrameCallbackが使える場合は
     * 新しいカメラフレームの数を数える。
     * 使えない場合はvideo.currentTimeで判定する。
     */
    this.videoFrameCallbackId = null;
    this.watchedVideo = null;
    this.videoFrameCount = 0;
    this.processedVideoFrameCount = -1;
    this.processedVideoTime = -1;
    this.lastVideoFrameCallbackTime = 0;

    /*
     * 接続ごとに増やす番号。
     *
     * カメラ起動中にdisconnectされた場合、
     * 古い起動処理を中断するために使用する。
     */
    this.connectionId =
      (this.connectionId || 0) + 1;

    /*
     * プレビュー描画ループのID
     *
     * disconnect時に停止し、
     * 再接続時にループが重複しないようにする。
     */
    this.previewAnimationFrameId = null;

    /*
     * segmentForVideoへ渡すタイムスタンプは
     * 単調増加にする必要がある。
     */
    this.lastSegmentationTimestamp = 0;

    /*
     * 人物画像のキャッシュ状態
     *
     * hasPersonCache:
     *   personCanvasに有効な人物画像があるか。
     *
     * lastMaskTime:
     *   最後に推論が成功した時刻。
     *
     * segmentationFailedAt:
     *   推論失敗が続いている場合の開始時刻。
     *   成功中はnull。
     */
    this.hasPersonCache = false;
    this.lastMaskTime = 0;
    this.segmentationFailedAt = null;

    /*
     * 実際のカメラ比率
     */
    this.videoAspectRatio = 4 / 3;

    this.cameraReady = false;
    this.segmenterReady = false;

    /*
     * デバッグ設定
     *
     * ?vb_debug=1 がない場合は常に既定値になり、
     * デバッグ用の計測・統計・描画は行わない。
     */
    this.debugConfig =
      this.parseDebugConfig(
        window.location.search
      );

    this.debugMetrics = null;
    this.debugMaskStats = null;
    this.debugCanvas = null;
    this.debugContext = null;

    this.setupDebugMode();

    this.setupCamera();
    this.setupSegmenter();
  }

  disconnect() {
    window.removeEventListener(
      "ai-roleplay:play-audio",
      this.handleAiAudio
    );
    
    this.stopPreviewLoop();
    this.stopVideoFrameWatcher();
    this.stopCamera();

    if (
      this.mediaRecorder &&
      this.mediaRecorder.state !== "inactive"
    ) {
      this.mediaRecorder.stop();
    } else {
      this.cleanupAudioMixer();
    }

    this.mediaRecorder = null;
    this.recordingStream = null;

    this.isDisconnected = true;
    this.connectionId++;

    if (this.segmenter) {
      try {
        this.segmenter.close();
      } catch (error) {
        console.warn(
          "ImageSegmenterの終了に失敗しました:",
          error
        );
      }
    }

    this.segmenter = null;
    this.segmenterDelegate = null;

    this.previousStableMask = null;
    this.maskImageData = null;
    this.refinedMaskBuffer = null;

    this.removeDebugCanvas();
    this.inferenceCanvas = null;
    this.inferenceContext = null;
    this.segmentationSizeLogKey = null;
    this.debugMetrics = null;
    this.debugMaskStats = null;
  }

  async setupCamera() {
    const connectionId =
      this.connectionId;

    try {
      const mediaStream =
        await navigator.mediaDevices.getUserMedia({
          video: {
            /*
             * 4:3を優先する。
             *
             * 1280×960が使えないカメラの場合は、
             * ブラウザが対応している4:3解像度を選択する。
             */
            width: {
              ideal: 1280
            },
            height: {
              ideal: 960
            },
            aspectRatio: {
              ideal: 4 / 3
            },
            frameRate: {
              ideal: 30,
              max: 30
            },
            facingMode: "user"
          },
          audio: true
        });

      /*
       * カメラの許可待ちの間に
       * disconnectされた場合は、
       * 取得したカメラを停止して終了する。
       */
      if (connectionId !== this.connectionId) {
        mediaStream
          .getTracks()
          .forEach((track) => {
            track.stop();
          });

        return;
      }

      this.mediaStream =
        mediaStream;

      this.sourceVideoTarget.srcObject =
        this.mediaStream;

      this.sourceVideoTarget.muted = true;
      this.sourceVideoTarget.playsInline = true;

      await this.sourceVideoTarget.play();

      /*
       * 再生開始待ちの間にdisconnectされた場合、
       * カメラはdisconnect側で停止済み。
       */
      if (connectionId !== this.connectionId) {
        return;
      }

      this.startVideoFrameWatcher(
        this.sourceVideoTarget
      );

      const actualWidth =
        this.sourceVideoTarget.videoWidth;

      const actualHeight =
        this.sourceVideoTarget.videoHeight;

      if (
        actualWidth > 0 &&
        actualHeight > 0
      ) {
        this.videoAspectRatio =
          actualWidth / actualHeight;
      }

      /*
       * 4:3を維持する。
       *
       * 実際のカメラが4:3ならそのまま。
       * その他の場合でも、表示側で
       * 無理に引き伸ばさない。
       */
      this.setupCanvasSize();

      this.startPreviewLoop();

      this.cameraReady = true;
      this.updateRecordingReadyState();
    } catch (error) {
      console.error(
        "カメラの起動に失敗しました:",
        error
      );
    }
  }

  setupCanvasSize() {
    const video =
      this.sourceVideoTarget;

    const canvas =
      this.previewTarget;

    if (
      video.videoWidth === 0 ||
      video.videoHeight === 0
    ) {
      return;
    }

    /*
     * 実際のカメラ解像度をCanvasに使用。
     *
     * 横方向・縦方向を別々に
     * 引き伸ばさない。
     */
    const width =
      video.videoWidth;

    const height =
      video.videoHeight;

    if (
      canvas.width !== width ||
      canvas.height !== height
    ) {
      canvas.width = width;
      canvas.height = height;

      this.frameCanvas.width =
        width;

      this.frameCanvas.height =
        height;

      this.personCanvas.width =
        width;

      this.personCanvas.height =
        height;

      this.resetMaskHistory();
    }
  }

  /*
   * 新しいカメラフレームが表示されるたびに
   * カウンタを進める。
   */
  startVideoFrameWatcher(video) {
    this.stopVideoFrameWatcher();

    if (
      typeof video.requestVideoFrameCallback !==
      "function"
    ) {
      return;
    }

    this.watchedVideo = video;

    const onVideoFrame = () => {
      if (
        this.isDisconnected ||
        this.watchedVideo !== video
      ) {
        return;
      }

      this.videoFrameCount++;

      this.lastVideoFrameCallbackTime =
        performance.now();

      this.videoFrameCallbackId =
        video.requestVideoFrameCallback(
          onVideoFrame
        );
    };

    this.videoFrameCallbackId =
      video.requestVideoFrameCallback(
        onVideoFrame
      );
  }

  stopVideoFrameWatcher() {
    if (
      this.watchedVideo &&
      this.videoFrameCallbackId !== null &&
      typeof this.watchedVideo.cancelVideoFrameCallback ===
        "function"
    ) {
      this.watchedVideo.cancelVideoFrameCallback(
        this.videoFrameCallbackId
      );
    }

    this.watchedVideo = null;
    this.videoFrameCallbackId = null;
  }

  stopCamera() {
    if (!this.mediaStream) {
      return;
    }

    this.mediaStream
      .getTracks()
      .forEach((track) => {
        track.stop();
      });

    this.mediaStream = null;
  }

  async cleanupAudioMixer() {
    if (this.microphoneSource) {
      try {
        this.microphoneSource.disconnect();
      } catch (error) {
        console.warn(
          "マイク音声の切断に失敗しました:",
          error
        );
      }

      this.microphoneSource = null;
    }

    if (this.recordingDestination) {
      this.recordingDestination.stream
        .getTracks()
        .forEach((track) => {
          track.stop();
        });

      this.recordingDestination = null;
    }

    if (this.audioContext) {
      try {
        if (
          this.audioContext.state !==
          "closed"
        ) {
          await this.audioContext.close();
        }
      } catch (error) {
        console.warn(
          "AudioContextの終了に失敗しました:",
          error
        );
      }

      this.audioContext = null;
    }
  }

  async handleAiAudio(event) {
    if (
      !this.audioContext ||
      !this.recordingDestination ||
      this.audioContext.state === "closed"
    ) {
      return;
    }

    const {
      audioBlob,
      markHandled,
      resolve,
      reject
    } = event.detail || {};

    if (!audioBlob) {
      return;
    }

    /*
     * Audio Mixer側で再生を担当することを
     * ai_roleplay_controllerへ通知する。
     */
    if (markHandled) {
      markHandled();
    }

    try {
      if (
        this.audioContext.state ===
        "suspended"
      ) {
        await this.audioContext.resume();
      }

      const arrayBuffer =
        await audioBlob.arrayBuffer();

      const audioBuffer =
        await this.audioContext.decodeAudioData(
          arrayBuffer
        );

      const source =
        this.audioContext.createBufferSource();

      source.buffer = audioBuffer;

      /*
       * AI音声をブラウザのスピーカーへ出力する。
       */
      source.connect(
        this.audioContext.destination
      );

      /*
       * 同じAI音声を録画用Audio Mixerにも送る。
       *
       * microphoneSourceも同じ
       * recordingDestinationへ接続されているため、
       * MediaRecorderには
       *
       * 店員マイク + AI顧客TTS
       *
       * の両方が入る。
       */
      source.connect(
        this.recordingDestination
      );

      source.addEventListener(
        "ended",
        () => {
          source.disconnect();

          if (resolve) {
            resolve();
          }
        },
        { once: true }
      );

      source.start();
    } catch (error) {
      console.error(
        "AI顧客音声のMixer再生に失敗しました:",
        error
      );

      if (reject) {
        reject(error);
      }
    }
  }

  async setupSegmenter() {
    const loadStartedAt =
      this.debugConfig.enabled
        ? performance.now()
        : 0;

    try {
      /*
       * WASMはimportmapで固定している
       * JS（@mediapipe/tasks-vision@1.0.1）と
       * 同じバージョンを使用する。
       */
      const vision =
        await FilesetResolver.forVisionTasks(
          "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm"
        );

      let delegate =
        this.debugConfig.delegate;

      let fallbackReason = null;

      let segmenter;

      if (delegate === "GPU") {
        /*
         * デバッグ用（?vb_debug=1&vb_delegate=gpu）
         *
         * GPUで初期化できない場合は
         * CPUで初期化し直す。
         */
        try {
          segmenter =
            await this.createSegmenter(
              vision,
              "GPU"
            );
        } catch (error) {
          fallbackReason =
            error && error.message
              ? error.message
              : String(error);

          console.warn(
            `[vb_debug] GPUの初期化に失敗したため、CPUで初期化し直します。理由: ${fallbackReason}`
          );

          if (this.isDisconnected) {
            return;
          }

          delegate = "CPU";
        }
      }

      if (!segmenter) {
        segmenter =
          await this.createSegmenter(
            vision,
            delegate
          );
      }

      /*
       * 読み込み中に画面を離れた場合は
       * すぐに解放する。
       */
      if (this.isDisconnected) {
        segmenter.close();
        return;
      }

      this.segmenter = segmenter;
      this.segmenterDelegate = delegate;

      if (this.debugConfig.enabled) {
        const delegateLabel =
          fallbackReason
            ? `${delegate}（GPUから切り替え）`
            : delegate;

        console.log(
          `[vb_debug] ImageSegmenterの準備が完了しました（model=${this.debugConfig.model}、delegate=${delegateLabel}、読み込み ${Math.round(performance.now() - loadStartedAt)}ms）`
        );
      }

      this.segmenterReady = true;
      this.updateRecordingReadyState();
    } catch (error) {
      console.error(
        "ImageSegmenterの起動に失敗しました:",
        error
      );

      if (this.isDisconnected) {
        return;
      }

      this.handleSegmenterFailure();
    }
  }

  /*
   * ImageSegmenterを作成する。
   *
   * CPUの場合はdelegateを指定しない
   * （MediaPipeの既定値のCPUで実行される）。
   * GPUはデバッグ時だけ指定される。
   */
  createSegmenter(
    vision,
    delegate
  ) {
    const baseOptions = {
      modelAssetPath:
        SEGMENTATION_MODELS[
          this.debugConfig.model
        ]
    };

    if (delegate === "GPU") {
      baseOptions.delegate = "GPU";
    }

    return ImageSegmenter.createFromOptions(
      vision,
      {
        baseOptions,

        runningMode: "VIDEO",

        outputConfidenceMasks: true,
        outputCategoryMask: false
      }
    );
  }

  /*
   * ImageSegmenterが使えない場合は
   * バーチャル背景を無効にし、
   * 通常のカメラ映像で録画できるようにする。
   */
  handleSegmenterFailure() {
    this.segmenterFailed = true;

    this.selectedBackground = null;
    this.backgroundImage = null;

    this.resetMaskHistory();

    this.backgroundButtonTargets.forEach(
      (backgroundButton) => {
        backgroundButton.disabled = true;

        backgroundButton.setAttribute(
          "aria-pressed",
          backgroundButton.dataset.background === "none"
            ? "true"
            : "false"
        );
      }
    );

    this.updateRecordingReadyState();
  }

  updateRecordingReadyState() {
    if (
      !this.cameraReady ||
      !(
        this.segmenterReady ||
        this.segmenterFailed
      )
    ) {
      return;
    }

    /*
     * 録画中は録画ボタンと
     * 状態表示を変更しない。
     */
    if (
      this.mediaRecorder &&
      this.mediaRecorder.state !== "inactive"
    ) {
      return;
    }

    this.startButtonTarget.disabled = false;

    if (this.hasStatusTarget) {
      this.statusTarget.textContent =
        this.segmenterFailed
          ? "バーチャル背景は利用できません"
          : "録画前プレビュー";
    }
  }


  selectBackground(event) {
    const button =
      event.currentTarget;

    const background =
      button.dataset.background;

    if (background === "none") {
      this.selectedBackground = null;
      this.backgroundImage = null;
    } else {
      this.selectedBackground =
        button.dataset.backgroundUrl;

      this.loadBackgroundImage(
        this.selectedBackground
      );
    }

    this.backgroundButtonTargets.forEach(
      (backgroundButton) => {
        backgroundButton.setAttribute(
          "aria-pressed",
          backgroundButton.dataset.background === background
            ? "true"
            : "false"
        );
      }
    );

    /*
     * 背景を変更したら
     * 古いマスクを破棄する。
     */
    this.resetMaskHistory();
  }
  loadBackgroundImage(src) {
    const image =
      new Image();

    image.onload = () => {
      this.backgroundImage =
        image;

      this.resetMaskHistory();
    };

    image.onerror = (error) => {
      console.error(
        "背景画像の読み込みに失敗しました:",
        error
      );

      this.backgroundImage = null;
    };

    image.src = src;
  }

  resetMaskHistory() {
    this.previousStableMask = null;

    /*
     * 古い人物画像を使わないよう、
     * 次のフレームで必ず推論し直す。
     */
    this.hasPersonCache = false;
    this.lastMaskTime = 0;
    this.segmentationFailedAt = null;
    this.processedVideoFrameCount = -1;
    this.processedVideoTime = -1;
  }

  /*
   * プレビュー描画ループを開始する。
   *
   * 既に予約済みのループがあれば停止し、
   * 常に1つのループだけが動くようにする。
   */
  startPreviewLoop() {
    this.stopPreviewLoop();
    this.drawPreview();
  }

  stopPreviewLoop() {
    if (this.previewAnimationFrameId !== null) {
      cancelAnimationFrame(
        this.previewAnimationFrameId
      );

      this.previewAnimationFrameId = null;
    }
  }

  drawPreview() {
    if (
      !this.hasPreviewTarget ||
      this.isDisconnected
    ) {
      return;
    }

    /*
     * 描画中に例外が発生しても
     * 次のフレームの描画を継続し、
     * プレビューと録画を止めない。
     */
    try {
      if (this.debugMetrics) {
        this.renderPreviewFrameWithMetrics();
      } else {
        this.renderPreviewFrame();
      }
    } catch (error) {
      console.error(
        "プレビューの描画に失敗しました:",
        error
      );
    } finally {
      /*
       * 予約済みのループがある場合は
       * 新たに予約しない。
       */
      if (
        !this.isDisconnected &&
        this.previewAnimationFrameId === null
      ) {
        this.previewAnimationFrameId =
          requestAnimationFrame(() => {
            this.previewAnimationFrameId = null;
            this.drawPreview();
          });
      }
    }
  }

  renderPreviewFrame() {
    const video =
      this.sourceVideoTarget;

    const canvas =
      this.previewTarget;

    const context =
      canvas.getContext("2d");

    if (
      video.readyState <
        HTMLMediaElement.HAVE_CURRENT_DATA ||
      video.videoWidth === 0 ||
      video.videoHeight === 0
    ) {
      return;
    }

    this.setupCanvasSize();

    const width =
      canvas.width;

    const height =
      canvas.height;

    if (
      this.selectedBackground &&
      this.backgroundImage
    ) {
      this.drawBackgroundWithPerson(
        video,
        context,
        width,
        height
      );
    } else {
      context.drawImage(
        video,
        0,
        0,
        width,
        height
      );
    }
  }

  drawBackgroundWithPerson(
    video,
    context,
    width,
    height
  ) {
    /*
     * まず背景を描画
     */
    this.drawBackground(
      context,
      width,
      height
    );

    /*
     * MediaPipeの準備待ち
     */
    if (!this.segmenter) {
      context.drawImage(
        video,
        0,
        0,
        width,
        height
      );

      return;
    }

    const now =
      performance.now();

    /*
     * 前回の処理中、または
     * 新しいカメラフレームがない場合は
     * 推論せず、前回の結果を描画する。
     *
     * personCanvasは推論に使った
     * フレームそのものから切り抜いているため、
     * マスクと人物画像はずれない。
     */
    if (
      this.isProcessing ||
      !this.shouldSegmentCurrentFrame(
        video,
        now
      )
    ) {
      this.drawSegmentedPerson(
        video,
        context,
        width,
        height,
        now
      );

      return;
    }

    this.isProcessing = true;

    let result = null;

    try {
      /*
       * 推論と切り抜きに同じ画像を使うため、
       * 先にカメラ映像を作業用Canvasへ取得する。
       */
      this.captureVideoFrame(
        video,
        width,
        height
      );

      const metrics =
        this.debugMetrics;

      const inferenceStartedAt =
        metrics
          ? performance.now()
          : 0;

      /*
       * 通常利用時はframeCanvasをそのまま推論する。
       *
       * vb_inputを指定したデバッグ時だけ、
       * frameCanvasを縮小した画像を推論する。
       * 縮小処理の時間も推論時間に含める。
       */
      const segmentationInput =
        this.debugConfig.inputWidth
          ? this.createSegmentationInput(
            width,
            height
          )
          : this.frameCanvas;

      result =
        this.segmenter.segmentForVideo(
          segmentationInput,
          this.nextSegmentationTimestamp(now)
        );

      if (metrics) {
        metrics.inferenceMs +=
          performance.now() -
          inferenceStartedAt;

        metrics.inferenceFrames++;
      }

      if (
        !result.confidenceMasks ||
        result.confidenceMasks.length === 0
      ) {
        throw new Error(
          "人物認識マスクを取得できませんでした"
        );
      }

      /*
       * 人物の確信度マスク（1チャンネル）
       */
      const confidenceMask =
        result.confidenceMasks[0];

      const maskStartedAt =
        metrics
          ? performance.now()
          : 0;

      const mask =
        confidenceMask.getAsFloat32Array();

      /*
       * マスクの読み出し時間
       * （GPUの場合はGPUの処理完了の待ち時間を含む）
       */
      if (metrics) {
        metrics.readMs +=
          performance.now() - maskStartedAt;
      }

      const maskWidth =
        confidenceMask.width;

      const maskHeight =
        confidenceMask.height;

      if (metrics) {
        this.logSegmentationSize(
          segmentationInput,
          maskWidth,
          maskHeight,
          width,
          height
        );
      }

      const refineStartedAt =
        metrics
          ? performance.now()
          : 0;

      const refinedMask =
        this.createRefinedMask(
          mask
        );

      if (metrics) {
        metrics.refineMs +=
          performance.now() - refineStartedAt;
      }

      this.drawPersonFromMask(
        this.frameCanvas,
        refinedMask,
        maskWidth,
        maskHeight,
        width,
        height
      );

      /*
       * デバッグモードの場合だけ
       * 計測・統計・デバッグ表示を行う。
       *
       * 推論結果を解放する前に
       * 元のマスクを参照する。
       */
      if (metrics) {
        metrics.maskMs +=
          performance.now() -
          maskStartedAt;

        metrics.maskFrames++;

        const statsStartedAt =
          performance.now();

        this.collectDebugMaskStats(
          mask,
          maskWidth,
          maskHeight,
          now
        );

        metrics.statsMs +=
          performance.now() - statsStartedAt;

        if (this.debugCanvas) {
          const debugViewStartedAt =
            performance.now();

          this.drawDebugView(
            mask,
            refinedMask,
            maskWidth,
            maskHeight
          );

          metrics.debugViewMs +=
            performance.now() -
            debugViewStartedAt;

          metrics.debugViewFrames++;
        }
      }

      this.hasPersonCache = true;
      this.lastMaskTime = now;
      this.segmentationFailedAt = null;
    } catch (error) {
      /*
       * 失敗が続いている間は
       * 同じエラーを毎フレーム出さない。
       */
      if (this.segmentationFailedAt === null) {
        console.error(
          "背景合成中にエラーが発生しました:",
          error
        );

        /*
         * 初期化の失敗と区別するため、
         * デバッグ時は推論中の失敗であることを表示する。
         */
        if (this.debugConfig.enabled) {
          console.warn(
            `[vb_debug] 推論中に失敗しました（delegate=${this.segmenterDelegate}）。前回の人物画像、またはカメラ映像の表示で続行します。`
          );
        }

        this.segmentationFailedAt = now;
      }
    } finally {
      /*
       * マスクのデータは描画までに
       * 使い終わっているため、
       * ここで推論結果を解放する。
       */
      if (result) {
        try {
          result.close();
        } catch (error) {
          console.warn(
            "推論結果の解放に失敗しました:",
            error
          );
        }
      }

      this.isProcessing = false;
    }

    this.drawSegmentedPerson(
      video,
      context,
      width,
      height,
      now
    );
  }

  /*
   * 新しいカメラフレームがあるか判定する。
   *
   * 人物画像のキャッシュがない場合は
   * 推論を試みる。
   */
  shouldSegmentCurrentFrame(video, now) {
    if (!this.hasPersonCache) {
      return true;
    }

    /*
     * requestVideoFrameCallbackが動作している場合は
     * 通知されたフレーム数で判定する。
     */
    if (
      this.watchedVideo === video &&
      this.videoFrameCount > 0
    ) {
      if (
        this.videoFrameCount !==
        this.processedVideoFrameCount
      ) {
        return true;
      }

      /*
       * 通知がFRAME_STALE_MS以内に届いていれば、
       * 新しいフレームはまだ来ていない。
       */
      if (
        now - this.lastVideoFrameCallbackTime <
        FRAME_STALE_MS
      ) {
        return false;
      }
    }

    /*
     * requestVideoFrameCallbackが使えない、
     * 一度も通知されない、または通知が停止した場合は
     * video.currentTimeで判定する。
     */
    return (
      video.currentTime !==
      this.processedVideoTime
    );
  }

  captureVideoFrame(
    video,
    width,
    height
  ) {
    this.processedVideoFrameCount =
      this.videoFrameCount;

    this.processedVideoTime =
      video.currentTime;

    this.frameContext.drawImage(
      video,
      0,
      0,
      width,
      height
    );
  }

  /*
   * デバッグ用（?vb_debug=1&vb_input=320）
   *
   * frameCanvasをアスペクト比を保ったまま縮小し、
   * 推論用の画像を作る。
   *
   * frameCanvas全体を推論用Canvas全体へ描画するため、
   * 座標は拡大・縮小だけで一致する。
   * 人物の切り抜きは元の解像度のframeCanvasで行う。
   *
   * 指定した幅がカメラ映像以上の場合は拡大せず、
   * frameCanvasをそのまま使う。
   */
  createSegmentationInput(
    width,
    height
  ) {
    const inputWidth =
      this.debugConfig.inputWidth;

    if (inputWidth >= width) {
      return this.frameCanvas;
    }

    const inputHeight =
      Math.max(
        1,
        Math.round(
          (height * inputWidth) / width
        )
      );

    if (!this.inferenceCanvas) {
      this.inferenceCanvas =
        document.createElement("canvas");

      this.inferenceContext =
        this.inferenceCanvas.getContext("2d");
    }

    if (
      this.inferenceCanvas.width !== inputWidth ||
      this.inferenceCanvas.height !== inputHeight
    ) {
      this.inferenceCanvas.width =
        inputWidth;

      this.inferenceCanvas.height =
        inputHeight;
    }

    this.inferenceContext.drawImage(
      this.frameCanvas,
      0,
      0,
      inputWidth,
      inputHeight
    );

    return this.inferenceCanvas;
  }

  /*
   * デバッグ用
   *
   * 推論用画像と返されたマスクの大きさを
   * 変わったときだけConsoleへ出す。
   */
  logSegmentationSize(
    segmentationInput,
    maskWidth,
    maskHeight,
    width,
    height
  ) {
    const inputSize =
      `${segmentationInput.width}x${segmentationInput.height}`;

    const maskSize =
      `${maskWidth}x${maskHeight}`;

    const key =
      `${inputSize}/${maskSize}/${width}x${height}`;

    if (this.segmentationSizeLogKey === key) {
      return;
    }

    this.segmentationSizeLogKey = key;

    console.log(
      `[vb_debug] 推論用画像 ${inputSize}（カメラ映像 ${width}x${height}）→ 返されたマスク ${maskSize}`
    );

    if (
      maskWidth !== segmentationInput.width ||
      maskHeight !== segmentationInput.height
    ) {
      console.warn(
        `[vb_debug] マスクの大きさ（${maskSize}）が推論用画像（${inputSize}）と異なります`
      );
    }
  }

  nextSegmentationTimestamp(now) {
    const timestamp =
      Math.max(
        now,
        this.lastSegmentationTimestamp + 1
      );

    this.lastSegmentationTimestamp =
      timestamp;

    return timestamp;
  }

  /*
   * 背景の上に人物を描画する。
   *
   * 推論成功中：
   *   最新の人物画像を描画。
   *
   * 推論失敗中：
   *   MASK_HOLD_MS以内なら前回の人物画像を描画。
   *   前回の人物画像は推論に使ったフレームから
   *   切り抜いているため、輪郭はずれない。
   *
   * 保持時間超過・人物画像なし：
   *   カメラ映像をそのまま描画。
   */
  drawSegmentedPerson(
    video,
    context,
    width,
    height,
    now
  ) {
    const canUsePersonCache =
      this.hasPersonCache &&
      (
        this.segmentationFailedAt === null ||
        now - this.lastMaskTime <= MASK_HOLD_MS
      );

    const source =
      canUsePersonCache
        ? this.personCanvas
        : video;

    context.drawImage(
      source,
      0,
      0,
      width,
      height
    );
  }

  drawBackground(
    context,
    width,
    height
  ) {
    if (!this.backgroundImage) {
      context.clearRect(
        0,
        0,
        width,
        height
      );

      return;
    }

    const image =
      this.backgroundImage;

    const imageRatio =
      image.width / image.height;

    const canvasRatio =
      width / height;

    let drawWidth;
    let drawHeight;
    let offsetX;
    let offsetY;

    /*
     * 背景画像は引き伸ばさず、
     * Canvasいっぱいになるように
     * 中央からトリミング。
     */
    if (
      imageRatio > canvasRatio
    ) {
      drawHeight =
        height;

      drawWidth =
        height * imageRatio;

      offsetX =
        (width - drawWidth) / 2;

      offsetY = 0;
    } else {
      drawWidth =
        width;

      drawHeight =
        width / imageRatio;

      offsetX = 0;

      offsetY =
        (height - drawHeight) / 2;
    }

    context.drawImage(
      image,
      offsetX,
      offsetY,
      drawWidth,
      drawHeight
    );
  }

  /*
   * 人物の確信度から各画素の不透明度（0〜1）を作る。
   *
   * MASK_ALPHA_HIGH以上は完全に不透明、
   * MASK_ALPHA_LOW以下は完全に透明にし、
   * その間だけを滑らかに変化させる。
   */
  createRefinedMask(mask) {
    const pixelCount =
      mask.length;

    const isFirstFrame =
      !this.previousStableMask ||
      this.previousStableMask.length !==
        pixelCount;

    if (isFirstFrame) {
      this.previousStableMask =
        new Float32Array(pixelCount);
    }

    if (
      !this.refinedMaskBuffer ||
      this.refinedMaskBuffer.length !==
        pixelCount
    ) {
      this.refinedMaskBuffer =
        new Float32Array(pixelCount);
    }

    /*
     * previousStableMaskには
     * フレーム間で安定化した確信度を保存する。
     */
    const stableMask =
      this.previousStableMask;

    const refinedMask =
      this.refinedMaskBuffer;

    /*
     * 通常利用時は定数の値。
     * デバッグモードではURLパラメータで
     * 一時的に変更した値を使用する。
     */
    const {
      alphaLow,
      alphaHigh,
      smoothing
    } = this.debugConfig;

    /*
     * vb_smooth=0 の場合は
     * 前フレームの値を使わない。
     */
    const smoothingWeight =
      smoothing
        ? MASK_SMOOTHING_WEIGHT
        : 0;

    const alphaRange =
      alphaHigh - alphaLow;

    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      const current =
        mask[i];

      const previous =
        stableMask[i];

      /*
       * フレーム間安定化
       *
       * 小さな変化（ちらつき）：
       *   上昇・下降とも同じ割合で平滑化。
       *
       * 大きな変化（人物の移動・画面外への退出）：
       *   平滑化せず、すぐに反映。
       */
      const stable =
        isFirstFrame ||
        Math.abs(current - previous) >
          MASK_MOTION_DIFF
          ? current
          : current * (1 - smoothingWeight) +
            previous * smoothingWeight;

      stableMask[i] =
        stable;

      if (stable <= alphaLow) {
        refinedMask[i] = 0;
      } else if (stable >= alphaHigh) {
        refinedMask[i] = 1;
      } else {
        /*
         * 輪郭部分
         *
         * smoothstepで段差のない
         * 透明度の変化にする。
         */
        const t =
          (stable - alphaLow) /
          alphaRange;

        refinedMask[i] =
          t * t * (3 - 2 * t);
      }
    }

    return refinedMask;
  }

  /*
   * 推論に使ったフレームから人物を切り抜き、
   * personCanvasへ保存する。
   *
   * 背景への描画はdrawSegmentedPersonで行う。
   */
  drawPersonFromMask(
    frameSource,
    mask,
    maskWidth,
    maskHeight,
    width,
    height
  ) {
    /*
     * デバッグ時だけ処理時間の内訳を計測する。
     */
    const metrics =
      this.debugMetrics;

    const drawStartedAt =
      metrics
        ? performance.now()
        : 0;

    /*
     * 人物Canvasを再利用
     */
    const personContext =
      this.personContext;

    /*
     * 書き換え中に失敗した場合、
     * 途中までの画像を使わないようにする。
     */
    this.hasPersonCache = false;

    personContext.globalCompositeOperation =
      "source-over";

    /*
     * カメラ映像はぼかさずに描画する。
     */
    personContext.filter =
      "none";

    personContext.clearRect(
      0,
      0,
      width,
      height
    );

    /*
     * 推論に使ったカメラフレーム
     */
    personContext.drawImage(
      frameSource,
      0,
      0,
      width,
      height
    );

    const maskCanvasStartedAt =
      metrics
        ? performance.now()
        : 0;

    /*
     * マスクCanvas
     */
    if (
      this.maskCanvas.width !==
        maskWidth ||
      this.maskCanvas.height !==
        maskHeight
    ) {
      this.maskCanvas.width =
        maskWidth;

      this.maskCanvas.height =
        maskHeight;

      this.maskImageData =
        this.maskContext.createImageData(
          maskWidth,
          maskHeight
        );
    }

    const maskImageData =
      this.maskImageData;

    const maskPixels =
      maskImageData.data;

    /*
     * マスクをAlpha値へ変換
     */
    for (
      let i = 0;
      i < mask.length;
      i++
    ) {
      const alpha =
        Math.max(
          0,
          Math.min(
            255,
            Math.round(
              mask[i] * 255
            )
          )
        );

      const pixelIndex =
        i * 4;

      maskPixels[pixelIndex] =
        255;

      maskPixels[pixelIndex + 1] =
        255;

      maskPixels[pixelIndex + 2] =
        255;

      maskPixels[pixelIndex + 3] =
        alpha;
    }

    this.maskContext.putImageData(
      maskImageData,
      0,
      0
    );

    const compositeStartedAt =
      metrics
        ? performance.now()
        : 0;

    if (metrics) {
      metrics.maskCanvasMs +=
        compositeStartedAt -
        maskCanvasStartedAt;
    }

    /*
     * 人物部分だけ残す
     */
    personContext.globalCompositeOperation =
      "destination-in";

    /*
     * マスクを拡大するときは
     * 高品質な補間で輪郭のギザギザを抑える。
     */
    personContext.imageSmoothingEnabled =
      true;

    personContext.imageSmoothingQuality =
      "high";

    /*
     * マスクの透明度だけをぼかし、
     * 輪郭を滑らかにする。
     *
     * 人物内部は不透明のまま残るため、
     * 顔や服の鮮明さは変わらない。
     */
    const edgeBlurPx =
      this.debugConfig.edgeBlurPx;

    if (edgeBlurPx > 0) {
      personContext.filter =
        `blur(${edgeBlurPx}px)`;
    }

    personContext.drawImage(
      this.maskCanvas,
      0,
      0,
      width,
      height
    );

    personContext.filter =
      "none";

    personContext.globalCompositeOperation =
      "source-over";

    /*
     * 切り抜きの時間
     * （カメラ映像の描画とマスクとの合成。マスクCanvasの更新は除く）
     */
    if (metrics) {
      metrics.compositeMs +=
        performance.now() -
        drawStartedAt -
        (compositeStartedAt -
          maskCanvasStartedAt);
    }
  }

  /*
   * ===== デバッグモード（?vb_debug=1） =====
   *
   * 人物認識モデルの比較と、
   * マスクの調整確認に使用する開発者向け機能。
   * 通常利用時は実行しない。
   */

  /*
   * URLパラメータからデバッグ設定を作る。
   *
   * vb_debug=1 がない場合は、
   * 他のパラメータをすべて無視して既定値を返す。
   */
  parseDebugConfig(search) {
    const config = {
      enabled: false,
      model: DEFAULT_SEGMENTATION_MODEL,
      inputWidth: null,
      delegate: DEFAULT_SEGMENTATION_DELEGATE,
      view: null,
      smoothing: true,
      alphaLow: MASK_ALPHA_LOW,
      alphaHigh: MASK_ALPHA_HIGH,
      edgeBlurPx: MASK_EDGE_BLUR_PX,
      warnings: []
    };

    let params;

    try {
      params =
        new URLSearchParams(search || "");
    } catch {
      return config;
    }

    if (params.get("vb_debug") !== "1") {
      return config;
    }

    config.enabled = true;

    const model =
      params.get("vb_model");

    if (model !== null) {
      if (
        Object.prototype.hasOwnProperty.call(
          SEGMENTATION_MODELS,
          model
        )
      ) {
        config.model = model;
      } else {
        config.warnings.push(
          `vb_model=${model} は無効です。${DEFAULT_SEGMENTATION_MODEL}を使用します。`
        );
      }
    }

    /*
     * 推論用画像の幅（整数）。
     * 未指定の場合はカメラ映像と同じ解像度で推論する。
     */
    const inputWidth =
      params.get("vb_input");

    if (inputWidth !== null) {
      const number =
        Number(inputWidth);

      if (
        /^\d+$/.test(inputWidth) &&
        number >= DEBUG_MIN_INPUT_WIDTH &&
        number <= DEBUG_MAX_INPUT_WIDTH
      ) {
        config.inputWidth = number;
      } else {
        config.warnings.push(
          `vb_input=${inputWidth} は無効です（${DEBUG_MIN_INPUT_WIDTH}〜${DEBUG_MAX_INPUT_WIDTH}の整数）。カメラ映像と同じ解像度で推論します。`
        );
      }
    }

    const delegate =
      params.get("vb_delegate");

    if (delegate !== null) {
      if (
        Object.prototype.hasOwnProperty.call(
          DEBUG_DELEGATES,
          delegate
        )
      ) {
        config.delegate =
          DEBUG_DELEGATES[delegate];
      } else {
        config.warnings.push(
          `vb_delegate=${delegate} は無効です（cpu、gpu）。${DEFAULT_SEGMENTATION_DELEGATE}を使用します。`
        );
      }
    }

    const view =
      params.get("vb_view");

    if (view !== null) {
      if (DEBUG_VIEWS.includes(view)) {
        config.view = view;
      } else {
        config.warnings.push(
          `vb_view=${view} は無効です。デバッグ表示を行いません。`
        );
      }
    }

    const smooth =
      params.get("vb_smooth");

    if (smooth === "0") {
      config.smoothing = false;
    } else if (
      smooth !== null &&
      smooth !== "1"
    ) {
      config.warnings.push(
        `vb_smooth=${smooth} は無効です。平滑化を有効にします。`
      );
    }

    const alphaLow =
      this.parseDebugNumberParam(
        params,
        "vb_low",
        0,
        1,
        MASK_ALPHA_LOW,
        config.warnings
      );

    const alphaHigh =
      this.parseDebugNumberParam(
        params,
        "vb_high",
        0,
        1,
        MASK_ALPHA_HIGH,
        config.warnings
      );

    /*
     * LOWがHIGH以上の場合は
     * 両方とも既定値を使用する。
     */
    if (alphaLow < alphaHigh) {
      config.alphaLow = alphaLow;
      config.alphaHigh = alphaHigh;
    } else {
      config.warnings.push(
        `vb_low=${alphaLow} がvb_high=${alphaHigh} 以上のため、既定値（${MASK_ALPHA_LOW} / ${MASK_ALPHA_HIGH}）を使用します。`
      );
    }

    config.edgeBlurPx =
      this.parseDebugNumberParam(
        params,
        "vb_blur",
        0,
        DEBUG_MAX_EDGE_BLUR_PX,
        MASK_EDGE_BLUR_PX,
        config.warnings
      );

    return config;
  }

  /*
   * 数値パラメータを読み取る。
   *
   * 未指定・数値以外・範囲外の場合は既定値を返す。
   */
  parseDebugNumberParam(
    params,
    name,
    min,
    max,
    defaultValue,
    warnings
  ) {
    const value =
      params.get(name);

    if (value === null) {
      return defaultValue;
    }

    const number =
      value.trim() === ""
        ? NaN
        : Number(value);

    if (
      !Number.isFinite(number) ||
      number < min ||
      number > max
    ) {
      warnings.push(
        `${name}=${value} は無効です（${min}〜${max}）。既定値${defaultValue}を使用します。`
      );

      return defaultValue;
    }

    return number;
  }

  setupDebugMode() {
    /*
     * Turboのキャッシュに残った
     * 古いデバッグ用Canvasを削除する。
     */
    this.removeDebugCanvas();

    if (!this.debugConfig.enabled) {
      return;
    }

    const config =
      this.debugConfig;

    console.log(
      "[vb_debug] デバッグモード",
      {
        model: config.model,
        inputWidth:
          config.inputWidth || "カメラ映像と同じ",
        delegate: config.delegate,
        view: config.view || "なし",
        smoothing: config.smoothing,
        alphaLow: config.alphaLow,
        alphaHigh: config.alphaHigh,
        edgeBlurPx: config.edgeBlurPx
      }
    );

    config.warnings.forEach((warning) => {
      console.warn(
        `[vb_debug] ${warning}`
      );
    });

    this.debugMetrics =
      this.createDebugMetrics(
        performance.now()
      );

    this.debugMaskStats = {
      nextAt:
        performance.now() +
        DEBUG_REPORT_INTERVAL_MS,
      baseline: null
    };

    if (config.view) {
      this.setupDebugCanvas();
    }
  }

  createDebugMetrics(startedAt) {
    return {
      startedAt,
      renderFrames: 0,
      renderMs: 0,
      inferenceFrames: 0,
      inferenceMs: 0,
      maskFrames: 0,
      maskMs: 0,
      debugViewFrames: 0,
      debugViewMs: 0,
      readMs: 0,
      refineMs: 0,
      maskCanvasMs: 0,
      compositeMs: 0,
      statsMs: 0
    };
  }

  /*
   * デバッグ表示用Canvasを作成する。
   *
   * 録画はpreview Canvasだけを使うため、
   * このCanvasの内容は録画映像に入らない。
   */
  setupDebugCanvas() {
    if (!this.hasPreviewTarget) {
      return;
    }

    const canvas =
      document.createElement("canvas");

    canvas.dataset.vbDebugCanvas =
      "true";

    canvas.className =
      "w-100 rounded mt-2 border";

    canvas.setAttribute(
      "aria-hidden",
      "true"
    );

    canvas.width = 640;
    canvas.height = 480;

    this.previewTarget.insertAdjacentElement(
      "afterend",
      canvas
    );

    this.debugCanvas = canvas;

    this.debugContext =
      canvas.getContext(
        "2d",
        { willReadFrequently: true }
      );

    this.debugContext.fillStyle =
      "#333";

    this.debugContext.fillRect(
      0,
      0,
      canvas.width,
      canvas.height
    );

    this.drawDebugLegend([
      `vb_view=${this.debugConfig.view}（録画されません）`,
      "バーチャル背景を選択すると表示されます"
    ]);

    if (this.debugConfig.view === "edge") {
      console.log(
        "[vb_debug] edge表示の凡例: " +
        "黄=輪郭（カメラ映像とバーチャル背景が混ざる部分） / " +
        "赤=元の背景が残っている可能性（推定：表示中だが現在フレームの確信度0.5未満） / " +
        "水色=人物が欠けている可能性（推定：確信度0.5以上だが透明度0.5未満）。" +
        "赤・水色は輪郭ぼかしの影響を含まない推定表示です。"
      );
    }
  }

  removeDebugCanvas() {
    if (this.element) {
      this.element
        .querySelectorAll(
          "[data-vb-debug-canvas]"
        )
        .forEach((canvas) => {
          canvas.remove();
        });
    }

    this.debugCanvas = null;
    this.debugContext = null;
  }

  renderPreviewFrameWithMetrics() {
    const metrics =
      this.debugMetrics;

    const startedAt =
      performance.now();

    const debugViewMsBefore =
      metrics.debugViewMs;

    try {
      this.renderPreviewFrame();
    } finally {
      const now =
        performance.now();

      /*
       * デバッグ表示の時間は
       * 描画時間に含めない。
       */
      metrics.renderMs +=
        now -
        startedAt -
        (metrics.debugViewMs -
          debugViewMsBefore);

      metrics.renderFrames++;

      this.reportDebugMetrics(now);
    }
  }

  /*
   * 一定間隔で処理時間とfpsを表示する。
   */
  reportDebugMetrics(now) {
    const metrics =
      this.debugMetrics;

    const elapsed =
      now - metrics.startedAt;

    if (elapsed < DEBUG_REPORT_INTERVAL_MS) {
      return;
    }

    const average = (total, count) =>
      count > 0
        ? (total / count).toFixed(2)
        : "-";

    const fps = (count) =>
      ((count * 1000) / elapsed).toFixed(1);

    let message =
      `[vb_debug] model=${this.debugConfig.model} delegate=${this.segmenterDelegate || "-"} ` +
      `推論 ${average(metrics.inferenceMs, metrics.inferenceFrames)}ms / ` +
      `マスク処理 ${average(metrics.maskMs, metrics.maskFrames)}ms / ` +
      `描画 ${average(metrics.renderMs, metrics.renderFrames)}ms / ` +
      `描画fps ${fps(metrics.renderFrames)} / ` +
      `推論fps ${fps(metrics.inferenceFrames)}`;

    if (metrics.debugViewFrames > 0) {
      message +=
        ` / デバッグ表示 ${average(metrics.debugViewMs, metrics.debugViewFrames)}ms（上記に含まない）`;
    }

    console.log(message);

    /*
     * マスク処理の内訳（推論1回あたりの平均）
     *
     * GPUの場合、segmentForVideoは処理を依頼して戻り、
     * 最初のgetAsFloat32Array()がGPUの処理完了を待つ。
     * 「推論+読み出し」がJavaScriptから見たGPU処理の所要時間。
     */
    if (metrics.maskFrames > 0) {
      const perMask = (total) =>
        (total / metrics.maskFrames).toFixed(2);

      const inferenceAverage =
        metrics.inferenceFrames > 0
          ? metrics.inferenceMs /
            metrics.inferenceFrames
          : 0;

      console.log(
        `[vb_debug] 内訳 読み出し（GPU待ち含む） ${perMask(metrics.readMs)}ms / ` +
        `平滑化・しきい値 ${perMask(metrics.refineMs)}ms / ` +
        `マスクCanvas ${perMask(metrics.maskCanvasMs)}ms / ` +
        `切り抜き ${perMask(metrics.compositeMs)}ms / ` +
        `統計 ${perMask(metrics.statsMs)}ms / ` +
        `推論+読み出し ${(inferenceAverage + metrics.readMs / metrics.maskFrames).toFixed(2)}ms`
      );
    }

    this.debugMetrics =
      this.createDebugMetrics(now);
  }

  /*
   * マスクの統計を一定間隔で表示する。
   *
   * 集計するときだけ元のマスクを1回コピーし、
   * 次の推論フレームと比較する。
   */
  collectDebugMaskStats(
    mask,
    maskWidth,
    maskHeight,
    now
  ) {
    const stats =
      this.debugMaskStats;

    if (!stats) {
      return;
    }

    if (!stats.baseline) {
      if (now >= stats.nextAt) {
        stats.baseline =
          new Float32Array(mask);
      }

      return;
    }

    const baseline =
      stats.baseline;

    stats.baseline = null;
    stats.nextAt =
      now + DEBUG_REPORT_INTERVAL_MS;

    if (baseline.length !== mask.length) {
      return;
    }

    const summary =
      this.calculateMaskStats(
        mask,
        baseline
      );

    console.log(
      `[vb_debug] マスク統計 model=${this.debugConfig.model}`,
      {
        size:
          `${maskWidth}x${maskHeight}`,
        histogram:
          summary.histogram,
        crossingPixels:
          summary.crossingPixels,
        crossingRatio:
          `${summary.crossingRatio}%`,
        edgePixels:
          summary.edgePixels,
        edgeMeanChange:
          summary.edgeMeanChange
      }
    );
  }

  /*
   * mask:     現在の推論フレームの確信度
   * baseline: 直前の推論フレームの確信度
   *
   * histogram:
   *   確信度0.1刻みの画素の割合
   *
   * crossingPixels:
   *   前フレームから確信度0.5をまたいだ画素数
   *
   * edgeMeanChange:
   *   どちらかのフレームで確信度が0.1〜0.9の画素の
   *   確信度の平均変化量
   */
  calculateMaskStats(mask, baseline) {
    const pixelCount =
      mask.length;

    const bins =
      new Array(10).fill(0);

    let crossingPixels = 0;
    let edgePixels = 0;
    let edgeChangeTotal = 0;

    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      const current =
        mask[i];

      const previous =
        baseline[i];

      const bin =
        Math.min(
          9,
          Math.max(
            0,
            Math.floor(current * 10)
          )
        );

      bins[bin]++;

      if (
        (current >= 0.5) !==
        (previous >= 0.5)
      ) {
        crossingPixels++;
      }

      if (
        (current > 0.1 && current < 0.9) ||
        (previous > 0.1 && previous < 0.9)
      ) {
        edgePixels++;

        edgeChangeTotal +=
          Math.abs(current - previous);
      }
    }

    const histogram = {};

    bins.forEach((count, index) => {
      const label =
        `${(index / 10).toFixed(1)}-${((index + 1) / 10).toFixed(1)}`;

      histogram[label] =
        `${((count / pixelCount) * 100).toFixed(1)}%`;
    });

    return {
      histogram,
      crossingPixels,
      crossingRatio:
        ((crossingPixels / pixelCount) * 100).toFixed(2),
      edgePixels,
      edgeMeanChange:
        edgePixels > 0
          ? Number((edgeChangeTotal / edgePixels).toFixed(4))
          : 0
    };
  }

  /*
   * デバッグ表示を描画する。
   *
   * confidence: 元の確信度（白=人物 / 黒=背景）
   * alpha:      最終的な透明度（白=不透明 / 黒=透明、ぼかし前）
   * edge:       カメラ映像に輪郭・推定箇所を色付け
   */
  drawDebugView(
    mask,
    refinedMask,
    maskWidth,
    maskHeight
  ) {
    const canvas =
      this.debugCanvas;

    const context =
      this.debugContext;

    if (!canvas || !context) {
      return;
    }

    if (
      canvas.width !== maskWidth ||
      canvas.height !== maskHeight
    ) {
      canvas.width = maskWidth;
      canvas.height = maskHeight;
    }

    const view =
      this.debugConfig.view;

    let imageData;

    if (view === "edge") {
      /*
       * 推論に使ったカメラフレームを
       * マスクと同じ大きさで描画する。
       */
      context.drawImage(
        this.frameCanvas,
        0,
        0,
        maskWidth,
        maskHeight
      );

      imageData =
        context.getImageData(
          0,
          0,
          maskWidth,
          maskHeight
        );
    } else {
      imageData =
        context.createImageData(
          maskWidth,
          maskHeight
        );
    }

    const pixels =
      imageData.data;

    for (
      let i = 0;
      i < mask.length;
      i++
    ) {
      const index =
        i * 4;

      if (view === "confidence" || view === "alpha") {
        const value =
          view === "confidence"
            ? mask[i]
            : refinedMask[i];

        const gray =
          Math.max(
            0,
            Math.min(
              255,
              Math.round(value * 255)
            )
          );

        pixels[index] = gray;
        pixels[index + 1] = gray;
        pixels[index + 2] = gray;
        pixels[index + 3] = 255;

        continue;
      }

      const confidence =
        mask[i];

      const alpha =
        refinedMask[i];

      let color = null;

      if (alpha >= 0.1 && confidence < 0.5) {
        /*
         * 赤（推定）：元の背景が残っている可能性
         */
        color = [255, 0, 0];
      } else if (confidence >= 0.5 && alpha < 0.5) {
        /*
         * 水色（推定）：人物が欠けている可能性
         */
        color = [0, 200, 255];
      } else if (alpha > 0 && alpha < 1) {
        /*
         * 黄：輪郭（カメラ映像とバーチャル背景が混ざる部分）
         */
        color = [255, 220, 0];
      }

      if (color) {
        pixels[index] =
          pixels[index] * 0.3 + color[0] * 0.7;

        pixels[index + 1] =
          pixels[index + 1] * 0.3 + color[1] * 0.7;

        pixels[index + 2] =
          pixels[index + 2] * 0.3 + color[2] * 0.7;
      } else {
        /*
         * 色付け以外の部分は暗くして見やすくする。
         */
        pixels[index] *= 0.5;
        pixels[index + 1] *= 0.5;
        pixels[index + 2] *= 0.5;
      }

      pixels[index + 3] = 255;
    }

    context.putImageData(
      imageData,
      0,
      0
    );

    if (view === "edge") {
      this.drawDebugLegend([
        "黄: 輪郭（映像と背景が混ざる部分）",
        "赤: 元の背景が残る可能性（推定）",
        "水色: 人物が欠ける可能性（推定）"
      ]);
    } else {
      this.drawDebugLegend([
        view === "confidence"
          ? "confidence: 元の確信度（白=人物 / 黒=背景）"
          : "alpha: 最終的な透明度（白=不透明 / 黒=透明、ぼかし前）"
      ]);
    }
  }

  drawDebugLegend(lines) {
    const canvas =
      this.debugCanvas;

    const context =
      this.debugContext;

    if (!canvas || !context) {
      return;
    }

    const fontSize =
      Math.max(
        10,
        Math.round(canvas.width / 32)
      );

    const lineHeight =
      Math.round(fontSize * 1.4);

    context.save();

    context.fillStyle =
      "rgba(0, 0, 0, 0.6)";

    context.fillRect(
      0,
      0,
      canvas.width,
      lineHeight * lines.length + fontSize * 0.6
    );

    context.font =
      `${fontSize}px sans-serif`;

    context.fillStyle =
      "#fff";

    context.textBaseline =
      "top";

    lines.forEach((line, index) => {
      context.fillText(
        line,
        fontSize * 0.4,
        fontSize * 0.3 + lineHeight * index
      );
    });

    context.restore();
  }

  async startRecording() {
    if (!this.mediaStream) {
      console.error(
        "カメラが起動していません"
      );

      return;
    }

    if (!this.hasPreviewTarget) {
      console.error(
        "プレビュー用canvasがありません"
      );

      return;
    }

    const canvas =
      this.previewTarget;

    /*
     * Canvasの現在の縦横比を
     * そのまま録画する。
     */
    const canvasStream =
      canvas.captureStream(30);

    /*
     * 店員のマイク音声とAI顧客の音声を
     * Web Audio APIで混合するための
     * AudioContextを作成する。
     */
    const AudioContextClass =
      window.AudioContext ||
      window.webkitAudioContext;

    if (!AudioContextClass) {
      console.error(
        "Web Audio APIに対応していません"
      );

      return;
    }

    try {
      this.audioContext =
        new AudioContextClass();

      if (
        this.audioContext.state ===
        "suspended"
      ) {
        await this.audioContext.resume();
      }

      /*
       * カメラ取得時に含まれている
       * マイク音声をAudioContextへ接続する。
       */
      this.microphoneSource =
        this.audioContext
          .createMediaStreamSource(
            this.mediaStream
          );

      /*
       * 録画専用の出力先。
       *
       * ここへ接続された音声が
       * MediaRecorderへ渡される。
       */
      this.recordingDestination =
        this.audioContext
          .createMediaStreamDestination();

      this.microphoneSource.connect(
        this.recordingDestination
      );

      /*
       * 混合済み音声トラックを
       * Canvasの映像Streamへ追加する。
       */
      this.recordingDestination.stream
        .getAudioTracks()
        .forEach((track) => {
          canvasStream.addTrack(track);
        });
    } catch (error) {
      console.error(
        "録音用Audio Mixerの作成に失敗しました:",
        error
      );

      await this.cleanupAudioMixer();

      return;
    }

    this.recordingStream =
      canvasStream;

    this.recordedChunks = [];

    let mimeType = "";

    if (
      MediaRecorder.isTypeSupported(
        "video/webm;codecs=vp9,opus"
      )
    ) {
      mimeType =
        "video/webm;codecs=vp9,opus";
    } else if (
      MediaRecorder.isTypeSupported(
        "video/webm;codecs=vp8,opus"
      )
    ) {
      mimeType =
        "video/webm;codecs=vp8,opus";
    } else {
      mimeType =
        "video/webm";
    }

    try {
      this.mediaRecorder =
        new MediaRecorder(
          this.recordingStream,
          {
            mimeType,
            videoBitsPerSecond: 4_000_000,
            audioBitsPerSecond: 128_000
          }
        );
    } catch (error) {
      console.error(
        "MediaRecorderの作成に失敗しました:",
        error
      );

      await this.cleanupAudioMixer();

      return;
    }

    this.mediaRecorder.ondataavailable =
      (event) => {
        if (event.data.size > 0) {
          this.recordedChunks.push(
            event.data
          );
        }
      };

    this.mediaRecorder.onstop =
      async () => {
        this.finishRecording();

        await this.cleanupAudioMixer();
      };

    this.mediaRecorder.start();

    if (this.hasStatusTarget) {
      this.statusTarget.textContent =
        "録画中";
    }

    this.startButtonTarget.disabled =
      true;

    this.stopButtonTarget.disabled =
      false;
  }

  stopRecording() {
    if (
      !this.mediaRecorder ||
      this.mediaRecorder.state ===
        "inactive"
    ) {
      return;
    }

    this.mediaRecorder.stop();

    this.stopButtonTarget.disabled =
      true;
  }

  finishRecording() {
    const blob =
      new Blob(
        this.recordedChunks,
        {
          type: "video/webm"
        }
      );
  
    this.recordedChunks = [];
  
    const video =
      document.createElement("video");
  
    const url =
      URL.createObjectURL(blob);
  
    video.preload = "metadata";
    video.src = url;
  
    video.onloadedmetadata = () => {
      const duration =
        video.duration;
  
      URL.revokeObjectURL(url);
  
      this.sendRecording(
        blob,
        duration
      );
    };
  
    video.onerror = () => {
      URL.revokeObjectURL(url);
  
      console.error(
        "録画動画の長さを取得できませんでした"
      );
    };
  }
  
  async sendRecording(blob, duration) {
    const formData =
      new FormData();

    formData.set(
      "video",
      blob,
      "practice_video.webm"
    );

    formData.set(
      "duration",
      duration
    );

    try {
      const csrfToken =
        document.querySelector(
          'meta[name="csrf-token"]'
        ).content;

      const response =
        await fetch(
          this.createUrlValue,
          {
            method: "POST",
            body: formData,
            headers: {
              Accept: "application/json",
              "X-CSRF-Token":
                csrfToken
            }
          }
        );

      if (!response.ok) {
        throw new Error(
          `HTTP ${response.status}`
        );
      }

      const result =
        await response.json();

      if (
        !result.success ||
        !result.analysis_id
      ) {
        throw new Error(
          "分析結果IDを取得できませんでした"
        );
      }

      window.location.href =
        `/analyses/${result.analysis_id}`;
    } catch (error) {
      console.error(
        "録画データの送信に失敗しました:",
        error
      );
    }
  }
}