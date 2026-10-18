import { Controller } from "@hotwired/stimulus";
import {
  ImageSegmenter,
  FilesetResolver,
  PoseLandmarker
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
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite",
  multiclass:
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/1/selfie_multiclass_256x256.tflite"
};

const DEFAULT_SEGMENTATION_MODEL = "landscape";

/*
 * MODNet（?vb_debug=1&vb_model=modnet）
 *
 * 比較検証用のポートレートマッティングモデル。
 * ONNX Runtime Web（WebGPU）で非同期に推論する。
 * 通常利用時は読み込まない。
 *
 * モデル：Xenova/modnet（Apache-2.0）のfp16版。リビジョンを固定する。
 * ライブラリ：onnxruntime-web 1.30.0（MIT）。
 *
 * 入出力（モデルとpreprocessor_config.jsonで確認）：
 *   input  float32 [1, 3, height, width]（RGB、(値 / 255 - 0.5) / 0.5）
 *   output float32 [1, 1, height, width]（透明度 0〜1）
 *   height・widthは32の倍数。
 *
 * 予備としてMediaPipe（landscape）も読み込み、
 * MODNetが使えない場合はMediaPipeで処理する。
 */
const MODNET_MODEL = "modnet";

const MODNET_ORT_URL =
  "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.30.0/dist/ort.webgpu.min.mjs";

const MODNET_MODEL_URL =
  "https://huggingface.co/Xenova/modnet/resolve/fa2fa546052fba4c08921230a26cc69a333fca12/onnx/model_fp16.onnx";

/*
 * 入力画像の短辺（?vb_modnet_size=）
 *
 * モデル設定の既定値は512。速度を優先して既定は256にする。
 * 縦横は32の倍数に切り下げる（モデル設定のsize_divisibility）。
 */
const MODNET_DEFAULT_SIZE = 256;
const MODNET_SIZES = [256, 320, 384, 448, 512];
const MODNET_SIZE_DIVISIBILITY = 32;

/*
 * 推論結果がこの時間を超えても返らない場合は
 * MODNetを停止し、MediaPipeへ戻す。
 */
const MODNET_TIMEOUT_MS = 3000;

/*
 * multiclassモデル（selfie_multiclass_256x256、約16MB）
 *
 * 比較検証用。?vb_debug=1&vb_model=multiclass の場合だけ使用する。
 *
 * confidenceMasksはクラスごとの確率（softmax）で、
 * 0番目は背景。人物の確信度は 1 - 背景 で求める。
 */
const MULTICLASS_MODEL = "multiclass";

const MULTICLASS_CATEGORIES = [
  "background",
  "hair",
  "body-skin",
  "face-skin",
  "clothes",
  "others"
];

const MULTICLASS_BACKGROUND_INDEX = 0;
const MULTICLASS_OTHERS_INDEX = 5;

/*
 * multiclassの人物マスクの計算方法（?vb_debug=1&vb_model=multiclass&vb_person=...）
 *
 * person = 1 - background - others × 重み
 *
 * 通常利用時は常にbg（othersも人物に含める）。
 */
const MULTICLASS_PERSON_MODES = {
  bg: 0,
  others_half: 0.5,
  no_others: 1
};

const DEFAULT_MULTICLASS_PERSON_MODE = "bg";

/*
 * クラス別表示（?vb_debug=1&vb_model=multiclass&vb_view=class）の色
 *
 * MULTICLASS_CATEGORIESと同じ順番。
 */
const MULTICLASS_CLASS_COLORS = [
  [64, 64, 64],
  [255, 230, 0],
  [255, 128, 0],
  [255, 79, 200],
  [30, 100, 255],
  [0, 224, 90]
];

const MULTICLASS_CLASS_COLOR_NAMES = [
  "濃い灰",
  "黄",
  "橙",
  "桃",
  "青",
  "緑"
];

/*
 * デバッグモード（?vb_debug=1）用の設定
 */
const DEBUG_VIEWS = [
  "confidence",
  "alpha",
  "edge"
];

/*
 * multiclassだけで使えるクラス別表示
 */
const DEBUG_CLASS_VIEW = "class";

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
 * landscapeモデル（入力256×144）の縦横比（?vb_debug=1&vb_aspect=fit）
 *
 * 推論用画像の左右に余白を追加して16:9にし、
 * MediaPipeによる引き伸ばしで人物の形が変わらないようにする。
 */
const LANDSCAPE_ASPECT_RATIO = 16 / 9;

/*
 * 推論の実行方法（?vb_debug=1&vb_delegate=gpu）
 *
 * 通常利用時は常にCPU。
 */
const DEFAULT_SEGMENTATION_DELEGATE = "CPU";

/*
 * 骨格の確認（?vb_debug=1&vb_pose=1）用のPose Landmarker
 *
 * lite版（float16、約5.8MB）。
 * モデルカード（BlazePose GHUM 3D）でApache License 2.0を確認済み。
 * 通常利用時は読み込まない。
 */
const POSE_MODEL_URL =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";

/*
 * 表示する点（MediaPipeの33点のうち肩・肘・手首）
 *
 * 左右は人物から見た左右。
 */
const POSE_ARM_POINTS = [
  { index: 11, name: "左肩" },
  { index: 12, name: "右肩" },
  { index: 13, name: "左肘" },
  { index: 14, name: "右肘" },
  { index: 15, name: "左手首" },
  { index: 16, name: "右手首" }
];

const POSE_ARM_CONNECTIONS = [
  [11, 12],
  [11, 13],
  [13, 15],
  [12, 14],
  [14, 16]
];

/*
 * visibilityの表示の区切り
 *
 * 0.7以上：緑、0.5〜0.7：黄、0.5未満：赤
 */
const POSE_VISIBILITY_HIGH = 0.7;
const POSE_VISIBILITY_LOW = 0.5;
const DEBUG_DELEGATES = {
  cpu: "CPU",
  gpu: "GPU"
};

/*
 * 2段階しきい値方式（?vb_debug=1&vb_mask=hysteresis）の既定値
 *
 * 比較検証用。通常利用時は使用しない。
 *
 * ENTER: 確信度がこの値以上なら人物状態にする。
 * KEEP:  人物状態の画素は、この値以上なら維持する（この値で不透明）。
 * EXIT:  人物状態の画素も、この値未満ならすぐに解除する（この値で透明）。
 * HOLD:  KEEP未満・EXIT以上の画素を維持する最大時間（ミリ秒）。
 * ENTER_TIMEOUT:
 *   ENTER以上の確信度が最後に確認されてから
 *   人物状態を維持する最大時間（ミリ秒）。0で無効。
 */
const HYSTERESIS_ENTER = 0.80;
const HYSTERESIS_KEEP = 0.50;
const HYSTERESIS_EXIT = 0.30;
const HYSTERESIS_HOLD_MS = 500;
const HYSTERESIS_MAX_HOLD_MS = 2000;
const HYSTERESIS_ENTER_TIMEOUT_MS = 0;
const HYSTERESIS_MIN_ENTER_TIMEOUT_MS = 100;
const HYSTERESIS_MAX_ENTER_TIMEOUT_MS = 10000;

/*
 * edge表示で「2段階しきい値で維持」とみなす透明度の差
 */
const HYSTERESIS_RETAINED_ALPHA_DIFF = 0.1;

const smoothstep = (edge0, edge1, value) => {
  if (value <= edge0) {
    return 0;
  }

  if (value >= edge1) {
    return 1;
  }

  const t =
    (value - edge0) /
    (edge1 - edge0);

  return t * t * (3 - 2 * t);
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

    /*
     * Pose Landmarker（?vb_debug=1&vb_pose=1 の場合だけ）
     *
     * 準備状態は録画の可否に関係させない。
     */
    this.poseLandmarker = null;
    this.poseDelegate = null;
    this.poseLandmarks = null;
    this.poseFailedAt = null;

    /*
     * vb_aspect=fit（デバッグ時のlandscapeのみ）
     */
    this.aspectFitCanvas = null;
    this.aspectFitContext = null;
    this.aspectFitLayout = null;
    this.aspectFitMaskBuffer = null;
    this.aspectFitDisabled = false;

    /*
     * MODNet（?vb_debug=1&vb_model=modnet の場合だけ）
     *
     * 準備ができるまで、または失敗した場合は
     * MediaPipe（landscape）で処理する。
     */
    this.modnetOrt = null;
    this.modnetSession = null;
    this.modnetFailed = false;
    this.modnetBusy = false;
    this.modnetBusySince = 0;
    this.modnetRequestId = 0;
    this.modnetFrameCanvas = null;
    this.modnetFrameContext = null;
    this.modnetInputCanvas = null;
    this.modnetInputContext = null;
    this.modnetInputBuffer = null;
    this.modnetAlphaBuffer = null;

    this.setupCamera();
    this.setupSegmenter();

    if (this.debugConfig.model === MODNET_MODEL) {
      this.setupModnet();
    }

    if (this.debugConfig.pose) {
      this.setupPoseLandmarker();
    }
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

    this.closePoseLandmarker(
      this.poseLandmarker
    );

    this.poseLandmarker = null;
    this.poseDelegate = null;
    this.poseLandmarks = null;
    this.poseFailedAt = null;

    this.releaseModnetSession(
      this.modnetSession
    );

    this.modnetSession = null;
    this.modnetOrt = null;
    this.modnetBusy = false;
    this.modnetFrameCanvas = null;
    this.modnetFrameContext = null;
    this.modnetInputCanvas = null;
    this.modnetInputContext = null;
    this.modnetInputBuffer = null;
    this.modnetAlphaBuffer = null;

    this.previousStableMask = null;
    this.maskImageData = null;
    this.refinedMaskBuffer = null;

    this.removeDebugCanvas();
    this.resetHysteresisState();
    this.multiclassPersonBuffer = null;
    this.debugClassImageData = null;
    this.aspectFitCanvas = null;
    this.aspectFitContext = null;
    this.aspectFitLayout = null;
    this.aspectFitMaskBuffer = null;
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
          `[vb_debug] ImageSegmenterの準備が完了しました（model=${this.debugConfig.model === MODNET_MODEL ? `${DEFAULT_SEGMENTATION_MODEL}（MODNetの予備）` : this.debugConfig.model}、delegate=${delegateLabel}、読み込み ${Math.round(performance.now() - loadStartedAt)}ms）`
        );

        if (
          this.debugConfig.model ===
          MULTICLASS_MODEL
        ) {
          console.log(
            `[vb_debug] multiclassのクラス: ${MULTICLASS_CATEGORIES.map((name, index) => `${index}=${name}`).join(", ")}（vb_person=${this.debugConfig.personMode}：${this.describeMulticlassPersonMode()}）`
          );
        }
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
    /*
     * vb_model=modnetの場合は、
     * 予備としてlandscapeを読み込む。
     */
    const baseOptions = {
      modelAssetPath:
        SEGMENTATION_MODELS[
          this.debugConfig.model
        ] ||
        SEGMENTATION_MODELS[
          DEFAULT_SEGMENTATION_MODEL
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
   * デバッグ用（?vb_debug=1&vb_model=modnet）
   *
   * ONNX Runtime Web（WebGPU）とMODNetを読み込む。
   * WebGPUが使えない場合や失敗した場合は、
   * MediaPipe（landscape）で続行する。
   *
   * 画面遷移などで接続が変わった場合は、
   * 作成したセッションをすぐに解放する。
   */
  async setupModnet() {
    const connectionId =
      this.connectionId;

    const isCurrentConnection = () =>
      !this.isDisconnected &&
      connectionId === this.connectionId;

    const loadStartedAt =
      performance.now();

    try {
      if (
        typeof navigator === "undefined" ||
        !navigator.gpu
      ) {
        throw new Error(
          "このブラウザではWebGPUを利用できません"
        );
      }

      const ort =
        await import(MODNET_ORT_URL);

      if (!isCurrentConnection()) {
        return;
      }

      /*
       * クロスオリジン分離をしていないため、
       * WASMはシングルスレッドで使用する。
       */
      ort.env.wasm.numThreads = 1;

      const session =
        await ort.InferenceSession.create(
          MODNET_MODEL_URL,
          {
            executionProviders: ["webgpu"]
          }
        );

      if (!isCurrentConnection()) {
        this.releaseModnetSession(session);
        return;
      }

      if (
        !session.inputNames.includes("input") ||
        !session.outputNames.includes("output")
      ) {
        this.releaseModnetSession(session);

        throw new Error(
          `MODNetの入出力名が想定と異なります（input: ${session.inputNames.join(",")} / output: ${session.outputNames.join(",")}）`
        );
      }

      this.modnetOrt = ort;
      this.modnetSession = session;

      console.log(
        `[vb_debug] MODNetの準備が完了しました（onnxruntime-web 1.30.0、WebGPU、fp16、短辺 ${this.debugConfig.modnetSize}px、後処理=${this.debugConfig.modnetPost}、読み込み ${Math.round(performance.now() - loadStartedAt)}ms）`
      );
    } catch (error) {
      if (!isCurrentConnection()) {
        return;
      }

      this.modnetFailed = true;

      console.warn(
        "[vb_debug] MODNetを起動できませんでした。MediaPipe（landscape）で続行します:",
        error
      );
    }
  }

  releaseModnetSession(session) {
    if (!session) {
      return;
    }

    try {
      const released =
        session.release();

      if (
        released &&
        typeof released.catch === "function"
      ) {
        released.catch((error) => {
          console.warn(
            "[vb_debug] MODNetのセッションの解放に失敗しました:",
            error
          );
        });
      }
    } catch (error) {
      console.warn(
        "[vb_debug] MODNetのセッションの解放に失敗しました:",
        error
      );
    }
  }

  /*
   * MODNetの推論中も画面を止めないため、
   * 描画は前回の結果（personCanvas）で毎フレーム行い、
   * 推論は1件ずつ非同期に実行する。
   */
  drawPersonWithModnet(
    video,
    context,
    width,
    height
  ) {
    const now =
      performance.now();

    /*
     * 結果が返らない場合はMODNetを停止し、
     * 次のフレームからMediaPipeで処理する。
     */
    if (
      this.modnetBusy &&
      now - this.modnetBusySince >
        MODNET_TIMEOUT_MS
    ) {
      this.stopModnet(
        `推論が${MODNET_TIMEOUT_MS}ms以内に終わりませんでした`
      );
    } else if (
      !this.modnetBusy &&
      this.shouldSegmentCurrentFrame(
        video,
        now
      )
    ) {
      this.startModnetInference(
        video,
        width,
        height,
        now
      );
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
   * 推論に使うフレームを専用のCanvasに保存し、
   * 結果が返ったら同じフレームから人物を切り抜く。
   * （推論中に次のフレームで上書きしない）
   */
  startModnetInference(
    video,
    width,
    height,
    now
  ) {
    const metrics =
      this.debugMetrics;

    const session =
      this.modnetSession;

    const ort =
      this.modnetOrt;

    const connectionId =
      this.connectionId;

    const requestId =
      ++this.modnetRequestId;

    let feeds;

    try {
      const preStartedAt =
        performance.now();

      if (!this.modnetFrameCanvas) {
        this.modnetFrameCanvas =
          document.createElement("canvas");

        this.modnetFrameContext =
          this.modnetFrameCanvas.getContext("2d");

        this.modnetInputCanvas =
          document.createElement("canvas");

        this.modnetInputContext =
          this.modnetInputCanvas.getContext(
            "2d",
            { willReadFrequently: true }
          );
      }

      if (
        this.modnetFrameCanvas.width !== width ||
        this.modnetFrameCanvas.height !== height
      ) {
        this.modnetFrameCanvas.width = width;
        this.modnetFrameCanvas.height = height;
      }

      this.processedVideoFrameCount =
        this.videoFrameCount;

      this.processedVideoTime =
        video.currentTime;

      this.modnetFrameContext.drawImage(
        video,
        0,
        0,
        width,
        height
      );

      const {
        inputWidth,
        inputHeight
      } = this.modnetInputSize(
        width,
        height
      );

      if (
        this.modnetInputCanvas.width !== inputWidth ||
        this.modnetInputCanvas.height !== inputHeight
      ) {
        this.modnetInputCanvas.width = inputWidth;
        this.modnetInputCanvas.height = inputHeight;
      }

      /*
       * モデル設定と同じく、32の倍数の大きさへ
       * フレーム全体を縮小する（切り取りや余白はない）。
       */
      this.modnetInputContext.drawImage(
        this.modnetFrameCanvas,
        0,
        0,
        inputWidth,
        inputHeight
      );

      const pixels =
        this.modnetInputContext.getImageData(
          0,
          0,
          inputWidth,
          inputHeight
        ).data;

      const pixelCount =
        inputWidth * inputHeight;

      if (
        !this.modnetInputBuffer ||
        this.modnetInputBuffer.length !==
          pixelCount * 3
      ) {
        this.modnetInputBuffer =
          new Float32Array(pixelCount * 3);
      }

      const input =
        this.modnetInputBuffer;

      /*
       * RGBA → RGBのNCHW。
       * (値 / 255 - 0.5) / 0.5 = 値 / 127.5 - 1
       */
      for (
        let i = 0;
        i < pixelCount;
        i++
      ) {
        const index =
          i * 4;

        input[i] =
          pixels[index] / 127.5 - 1;

        input[pixelCount + i] =
          pixels[index + 1] / 127.5 - 1;

        input[pixelCount * 2 + i] =
          pixels[index + 2] / 127.5 - 1;
      }

      feeds = {
        input: new ort.Tensor(
          "float32",
          input,
          [1, 3, inputHeight, inputWidth]
        )
      };

      if (metrics) {
        metrics.modnetPreMs +=
          performance.now() - preStartedAt;
      }

      this.modnetBusy = true;
      this.modnetBusySince = now;

      const runStartedAt =
        performance.now();

      session
        .run(feeds)
        .then((outputs) => {
          const isCurrent =
            connectionId === this.connectionId &&
            !this.isDisconnected &&
            session === this.modnetSession &&
            requestId === this.modnetRequestId &&
            !this.modnetFailed;

          const output =
            outputs.output;

          try {
            if (!isCurrent) {
              return;
            }

            const currentMetrics =
              this.debugMetrics;

            if (currentMetrics) {
              currentMetrics.modnetMs +=
                performance.now() - runStartedAt;

              currentMetrics.modnetFrames++;
            }

            this.applyModnetResult(
              output,
              inputWidth,
              inputHeight,
              width,
              height
            );
          } finally {
            if (
              output &&
              typeof output.dispose === "function"
            ) {
              output.dispose();
            }
          }
        })
        .catch((error) => {
          if (
            connectionId === this.connectionId &&
            !this.isDisconnected &&
            requestId === this.modnetRequestId
          ) {
            this.stopModnet(
              "推論に失敗しました",
              error
            );
          }
        })
        .finally(() => {
          if (requestId === this.modnetRequestId) {
            this.modnetBusy = false;
          }
        });
    } catch (error) {
      this.modnetBusy = false;

      this.stopModnet(
        "推論を開始できませんでした",
        error
      );
    }
  }

  /*
   * モデル設定（shortest_edge、size_divisibility=32）に従い、
   * 短辺をvb_modnet_sizeに合わせてから32の倍数に切り下げる。
   */
  modnetInputSize(
    width,
    height
  ) {
    const shortEdge =
      this.debugConfig.modnetSize;

    const scale =
      shortEdge / Math.min(width, height);

    const floorTo = (value) =>
      Math.max(
        MODNET_SIZE_DIVISIBILITY,
        Math.floor(value / MODNET_SIZE_DIVISIBILITY) *
          MODNET_SIZE_DIVISIBILITY
      );

    return {
      inputWidth:
        floorTo(Math.round(width * scale)),
      inputHeight:
        floorTo(Math.round(height * scale))
    };
  }

  /*
   * MODNetの透明度で、推論に使ったフレームから人物を切り抜く。
   *
   * raw：透明度を0〜1に収めてそのまま使う。
   * refine：既存のしきい値・平滑化（vb_maskを含む）を通す。
   */
  applyModnetResult(
    output,
    maskWidth,
    maskHeight,
    width,
    height
  ) {
    const metrics =
      this.debugMetrics;

    const postStartedAt =
      metrics
        ? performance.now()
        : 0;

    const alpha =
      output.data;

    const pixelCount =
      maskWidth * maskHeight;

    if (
      !output.dims ||
      output.dims.join("x") !==
        `1x1x${maskHeight}x${maskWidth}` ||
      alpha.length !== pixelCount
    ) {
      throw new Error(
        `MODNetの出力の形が想定と異なります（${output.dims ? output.dims.join("x") : "-"}）`
      );
    }

    if (
      !this.modnetAlphaBuffer ||
      this.modnetAlphaBuffer.length !==
        pixelCount
    ) {
      this.modnetAlphaBuffer =
        new Float32Array(pixelCount);
    }

    const mask =
      this.modnetAlphaBuffer;

    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      const value =
        alpha[i];

      /*
       * NaNは0（背景）として扱う。
       */
      mask[i] =
        value > 0
          ? Math.min(value, 1)
          : 0;
    }

    const now =
      performance.now();

    let refinedMask = mask;

    if (this.debugConfig.modnetPost === "refine") {
      refinedMask =
        this.debugConfig.maskMode === "hysteresis"
          ? this.createHysteresisMask(
            mask,
            now
          )
          : this.createRefinedMask(
            mask
          );
    }

    this.drawPersonFromMask(
      this.modnetFrameCanvas,
      refinedMask,
      maskWidth,
      maskHeight,
      width,
      height
    );

    if (metrics) {
      metrics.modnetPostMs +=
        performance.now() - postStartedAt;

      if (this.debugCanvas) {
        const debugViewStartedAt =
          performance.now();

        this.drawDebugView(
          mask,
          refinedMask,
          maskWidth,
          maskHeight,
          null,
          this.modnetFrameCanvas
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
  }

  /*
   * MODNetを停止し、以降はMediaPipe（landscape）で処理する。
   */
  stopModnet(
    reason,
    error
  ) {
    if (this.modnetFailed) {
      return;
    }

    this.modnetFailed = true;
    this.modnetBusy = false;

    /*
     * 実行中の推論の結果を使わない。
     */
    this.modnetRequestId++;

    console.warn(
      `[vb_debug] MODNet: ${reason}。MediaPipe（landscape）で続行します。`,
      ...(error ? [error] : [])
    );
  }

  reportModnetMetrics(
    metrics,
    elapsed
  ) {
    if (!this.modnetSession || this.modnetFailed) {
      console.log(
        `[vb_debug] MODNet ${this.modnetFailed ? "停止中（MediaPipeで処理）" : "準備中（MediaPipeで処理）"}`
      );

      return;
    }

    const average = (total) =>
      metrics.modnetFrames > 0
        ? (total / metrics.modnetFrames).toFixed(2)
        : "-";

    const input =
      this.modnetInputCanvas
        ? `${this.modnetInputCanvas.width}x${this.modnetInputCanvas.height}`
        : "-";

    console.log(
      `[vb_debug] MODNet 推論 ${average(metrics.modnetMs)}ms（非同期、更新 ${((metrics.modnetFrames * 1000) / elapsed).toFixed(1)}回/秒）/ ` +
      `前処理 ${average(metrics.modnetPreMs)}ms / 後処理・切り抜き ${average(metrics.modnetPostMs)}ms / ` +
      `入力 ${input} / 後処理=${this.debugConfig.modnetPost}`
    );
  }

  /*
   * デバッグ用（?vb_debug=1&vb_pose=1）
   *
   * Pose Landmarkerを作成する。
   * 失敗しても背景合成と録画は続行する。
   *
   * 画面遷移などで接続が変わった場合は、
   * 作成したPose Landmarkerをすぐに解放する。
   */
  async setupPoseLandmarker() {
    const connectionId =
      this.connectionId;

    const isCurrentConnection = () =>
      !this.isDisconnected &&
      connectionId === this.connectionId;

    const loadStartedAt =
      performance.now();

    try {
      const vision =
        await FilesetResolver.forVisionTasks(
          "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm"
        );

      if (!isCurrentConnection()) {
        return;
      }

      let delegate =
        this.debugConfig.delegate;

      let landmarker = null;

      if (delegate === "GPU") {
        try {
          landmarker =
            await this.createPoseLandmarker(
              vision,
              "GPU"
            );
        } catch (error) {
          console.warn(
            `[vb_debug] PoseのGPU初期化に失敗したため、CPUで初期化し直します。理由: ${error && error.message ? error.message : String(error)}`
          );

          delegate = "CPU";
        }

        if (!isCurrentConnection()) {
          this.closePoseLandmarker(landmarker);
          return;
        }
      }

      if (!landmarker) {
        landmarker =
          await this.createPoseLandmarker(
            vision,
            "CPU"
          );
      }

      if (!isCurrentConnection()) {
        this.closePoseLandmarker(landmarker);
        return;
      }

      this.poseLandmarker = landmarker;
      this.poseDelegate = delegate;

      console.log(
        `[vb_debug] Pose Landmarkerの準備が完了しました（lite、delegate=${delegate}、読み込み ${Math.round(performance.now() - loadStartedAt)}ms）`
      );
    } catch (error) {
      if (!isCurrentConnection()) {
        return;
      }

      console.warn(
        "[vb_debug] Pose Landmarkerを起動できませんでした。骨格を表示せずに続行します（背景合成と録画は継続します）:",
        error
      );
    }
  }

  createPoseLandmarker(
    vision,
    delegate
  ) {
    const baseOptions = {
      modelAssetPath:
        POSE_MODEL_URL
    };

    if (delegate === "GPU") {
      baseOptions.delegate = "GPU";
    }

    return PoseLandmarker.createFromOptions(
      vision,
      {
        baseOptions,

        runningMode: "VIDEO",

        numPoses: 1,
        outputSegmentationMasks: false
      }
    );
  }

  closePoseLandmarker(landmarker) {
    if (!landmarker) {
      return;
    }

    try {
      landmarker.close();
    } catch (error) {
      console.warn(
        "[vb_debug] Pose Landmarkerの終了に失敗しました:",
        error
      );
    }
  }

  /*
   * デバッグ用（?vb_debug=1&vb_pose=1）
   *
   * 人物認識と同じ画像・タイムスタンプで骨格を推定し、
   * 肩・肘・手首をデバッグ用Canvasに重ねる。
   *
   * 結果は人物マスクに使用しない。
   * 失敗した場合や人物がいない場合は、骨格を表示しない。
   */
  detectPoseForDebug(
    input,
    timestamp
  ) {
    const metrics =
      this.debugMetrics;

    const startedAt =
      performance.now();

    let result = null;
    let failed = false;

    try {
      result =
        this.poseLandmarker.detectForVideo(
          input,
          timestamp
        );

      const landmarks =
        result.landmarks &&
        result.landmarks[0];

      /*
       * 推論結果を解放した後も使えるよう、
       * 必要な値だけを取り出す。
       */
      this.poseLandmarks =
        landmarks
          ? POSE_ARM_POINTS.map(({ index, name }) => {
            const point =
              landmarks[index];

            return point
              ? {
                index,
                name,
                x: point.x,
                y: point.y,
                visibility:
                  Number.isFinite(point.visibility)
                    ? point.visibility
                    : 0
              }
              : null;
          })
          : null;

      if (metrics && landmarks) {
        metrics.poseDetectedFrames++;
      }

      this.poseFailedAt = null;
    } catch (error) {
      failed = true;
      this.poseLandmarks = null;

      if (metrics) {
        metrics.poseFailedFrames++;
      }

      if (this.poseFailedAt === null) {
        console.warn(
          "[vb_debug] Poseの推論に失敗しました。骨格を表示せずに続行します:",
          error
        );

        this.poseFailedAt = startedAt;
      }
    } finally {
      if (
        result &&
        typeof result.close === "function"
      ) {
        try {
          result.close();
        } catch (error) {
          console.warn(
            "[vb_debug] Poseの推論結果の解放に失敗しました:",
            error
          );
        }
      }

      if (metrics) {
        metrics.poseMs +=
          performance.now() - startedAt;

        metrics.poseFrames++;
      }
    }

    this.drawPoseOverlay(failed);
  }

  /*
   * 肩・肘・手首を線でつなぎ、
   * visibilityで色分けして描画する。
   *
   * 座標は推論用画像に対する0〜1の割合で、
   * デバッグ用Canvasは推論用画像（マスク）と同じ大きさ。
   */
  drawPoseOverlay(failed) {
    const canvas =
      this.debugCanvas;

    const context =
      this.debugContext;

    if (!canvas || !context) {
      return;
    }

    const points =
      this.poseLandmarks;

    if (!points) {
      this.drawPoseLegend(
        failed
          ? "Pose: 推論に失敗しました"
          : "Pose: 人物を検出できません"
      );

      return;
    }

    const width =
      canvas.width;

    const height =
      canvas.height;

    const pointByIndex =
      new Map(
        points
          .filter(Boolean)
          .map((point) => [point.index, point])
      );

    const colorFor = (visibility) =>
      visibility >= POSE_VISIBILITY_HIGH
        ? "rgb(0, 230, 90)"
        : visibility >= POSE_VISIBILITY_LOW
          ? "rgb(255, 220, 0)"
          : "rgb(255, 40, 40)";

    const lineWidth =
      Math.max(
        2,
        Math.round(width / 120)
      );

    context.save();

    context.lineWidth = lineWidth;
    context.lineCap = "round";

    POSE_ARM_CONNECTIONS.forEach(([from, to]) => {
      const start =
        pointByIndex.get(from);

      const end =
        pointByIndex.get(to);

      if (!start || !end) {
        return;
      }

      const visibility =
        Math.min(
          start.visibility,
          end.visibility
        );

      /*
       * どちらかの点のvisibilityが低い線は破線にする。
       */
      context.setLineDash(
        visibility >= POSE_VISIBILITY_HIGH
          ? []
          : [lineWidth * 2, lineWidth * 2]
      );

      context.strokeStyle =
        colorFor(visibility);

      context.beginPath();
      context.moveTo(
        start.x * width,
        start.y * height
      );
      context.lineTo(
        end.x * width,
        end.y * height
      );
      context.stroke();
    });

    context.setLineDash([]);

    const fontSize =
      Math.max(
        10,
        Math.round(width / 32)
      );

    context.font =
      `${fontSize}px sans-serif`;

    context.textBaseline =
      "bottom";

    let outsidePoints = 0;

    points.forEach((point) => {
      if (!point) {
        return;
      }

      if (
        point.x < 0 ||
        point.x > 1 ||
        point.y < 0 ||
        point.y > 1
      ) {
        outsidePoints++;
      }

      const x =
        point.x * width;

      const y =
        point.y * height;

      context.fillStyle =
        colorFor(point.visibility);

      context.beginPath();
      context.arc(
        x,
        y,
        lineWidth * 1.5,
        0,
        Math.PI * 2
      );
      context.fill();

      context.fillText(
        point.visibility.toFixed(2),
        x + lineWidth * 2,
        y - lineWidth
      );
    });

    context.restore();

    this.drawPoseLegend(
      `Pose（visibility）: 緑=${POSE_VISIBILITY_HIGH}以上 / 黄=${POSE_VISIBILITY_LOW}〜${POSE_VISIBILITY_HIGH} / 赤=${POSE_VISIBILITY_LOW}未満・破線` +
        (outsidePoints > 0
          ? ` / 画面外 ${outsidePoints}点`
          : "")
    );
  }

  /*
   * 骨格の説明をデバッグ用Canvasの下端に描画する。
   * （既存の凡例は上端）
   */
  drawPoseLegend(text) {
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

    const boxHeight =
      Math.round(fontSize * 1.6);

    context.save();

    context.fillStyle =
      "rgba(0, 0, 0, 0.6)";

    context.fillRect(
      0,
      canvas.height - boxHeight,
      canvas.width,
      boxHeight
    );

    context.font =
      `${fontSize}px sans-serif`;

    context.fillStyle =
      "#fff";

    context.textBaseline =
      "top";

    context.fillText(
      text,
      fontSize * 0.4,
      canvas.height - boxHeight + fontSize * 0.3
    );

    context.restore();
  }

  /*
   * 人物認識に失敗したフレームでは、
   * 古い骨格を残さないようにデバッグ表示を消す。
   */
  clearPoseDebugView(message) {
    this.poseLandmarks = null;

    const canvas =
      this.debugCanvas;

    const context =
      this.debugContext;

    if (!canvas || !context) {
      return;
    }

    context.clearRect(
      0,
      0,
      canvas.width,
      canvas.height
    );

    this.drawPoseLegend(
      `Pose: ${message}`
    );
  }

  /*
   * Poseの処理時間と、最後に検出した点のvisibilityを表示する。
   */
  reportPoseMetrics(metrics) {
    if (!this.poseLandmarker) {
      console.log(
        "[vb_debug] Pose 準備中、または利用できません（骨格表示なし）"
      );

      return;
    }

    const average =
      metrics.poseFrames > 0
        ? (metrics.poseMs / metrics.poseFrames).toFixed(2)
        : "-";

    const visibility = {};

    if (this.poseLandmarks) {
      this.poseLandmarks.forEach((point) => {
        if (point) {
          visibility[point.name] =
            Number(point.visibility.toFixed(2));
        }
      });
    }

    console.log(
      `[vb_debug] Pose 推論 ${average}ms（delegate=${this.poseDelegate}、${metrics.poseFrames}回、検出 ${metrics.poseDetectedFrames}回、失敗 ${metrics.poseFailedFrames}回、描画時間に含む）`,
      this.poseLandmarks
        ? visibility
        : "未検出"
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

    /*
     * 2段階しきい値方式の人物状態も破棄する。
     */
    this.resetHysteresisState();
  }

  /*
   * 2段階しきい値方式の人物状態を破棄する。
   *
   * 通常利用時は配列を作らないため、
   * 何もしない。
   */
  resetHysteresisState() {
    this.hysteresisState = null;
    this.hysteresisConfirmedAt = null;
    this.hysteresisEnteredAt = null;
    this.hysteresisRetainedFlags = null;
    this.hysteresisEpoch = 0;
    this.hysteresisLastUpdateAt = null;
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
     * デバッグ用（?vb_debug=1&vb_model=modnet）
     *
     * MODNetの準備ができている場合は、
     * 非同期の推論結果で人物を描画する。
     */
    if (
      this.modnetSession &&
      !this.modnetFailed
    ) {
      this.drawPersonWithModnet(
        video,
        context,
        width,
        height
      );

      return;
    }

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
      const baseSegmentationInput =
        this.debugConfig.inputWidth
          ? this.createSegmentationInput(
            width,
            height
          )
          : this.frameCanvas;

      /*
       * vb_aspect=fit（デバッグ時のlandscapeのみ）：
       *   左右に余白を追加した16:9の画像を推論する。
       *
       * それ以外は従来どおり。
       */
      const segmentationInput =
        this.debugConfig.aspectFit &&
        !this.aspectFitDisabled
          ? this.createAspectFitInput(
            baseSegmentationInput
          )
          : baseSegmentationInput;

      const segmentationTimestamp =
        this.nextSegmentationTimestamp(now);

      result =
        this.segmenter.segmentForVideo(
          segmentationInput,
          segmentationTimestamp
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
       * landscape・square：人物の確信度マスク（1チャンネル）
       * multiclass：背景の確率マスク（6チャンネルの0番目）
       *
       * 大きさの取得に使用する。
       */
      const confidenceMask =
        result.confidenceMasks[0];

      const maskStartedAt =
        metrics
          ? performance.now()
          : 0;

      /*
       * landscape・square：
       *   1チャンネルの人物確信度をそのまま使用。
       *
       * multiclass：
       *   背景の確率から人物の確信度へ変換する。
       */
      const rawMask =
        this.debugConfig.model === MULTICLASS_MODEL
          ? this.createMulticlassPersonMask(
            result.confidenceMasks,
            now
          )
          : confidenceMask.getAsFloat32Array();

      /*
       * landscape・squareの読み出し時間。
       * multiclassはcreateMulticlassPersonMaskの中で計測する。
       */
      if (
        metrics &&
        this.debugConfig.model !== MULTICLASS_MODEL
      ) {
        metrics.readMs +=
          performance.now() - maskStartedAt;
      }

      if (metrics) {
        this.logSegmentationSize(
          segmentationInput,
          confidenceMask.width,
          confidenceMask.height,
          width,
          height
        );
      }

      /*
       * vb_aspect=fitの場合は、
       * 左右の余白を除いて元の推論用画像の大きさに戻す。
       */
      const aspectFitMask =
        segmentationInput === this.aspectFitCanvas
          ? this.cropAspectFitMask(
            rawMask,
            confidenceMask.width,
            confidenceMask.height
          )
          : null;

      const mask =
        aspectFitMask
          ? aspectFitMask.mask
          : rawMask;

      const maskWidth =
        aspectFitMask
          ? aspectFitMask.width
          : confidenceMask.width;

      const maskHeight =
        aspectFitMask
          ? aspectFitMask.height
          : confidenceMask.height;

      /*
       * 通常利用時は常にcreateRefinedMask。
       * 2段階しきい値方式はデバッグモードの比較用。
       */
      const refineStartedAt =
        metrics
          ? performance.now()
          : 0;

      const refinedMask =
        this.debugConfig.maskMode === "hysteresis"
          ? this.createHysteresisMask(
            mask,
            now
          )
          : this.createRefinedMask(
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
            maskHeight,
            result.confidenceMasks
          );

          metrics.debugViewMs +=
            performance.now() -
            debugViewStartedAt;

          metrics.debugViewFrames++;

          /*
           * 骨格の確認（?vb_debug=1&vb_pose=1）
           *
           * 人物マスクには使用しない。
           * 推論と同じ画像・タイムスタンプで実行し、
           * デバッグ用Canvasに重ねて描画する。
           */
          if (this.poseLandmarker) {
            this.detectPoseForDebug(
              baseSegmentationInput,
              segmentationTimestamp
            );
          }
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

      /*
       * 骨格の確認中は、推論に失敗したフレームで
       * 古い骨格を表示し続けない。
       */
      if (this.poseLandmarker) {
        this.clearPoseDebugView(
          "推論に失敗したため骨格を表示していません"
        );
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
   * デバッグ用（?vb_debug=1&vb_aspect=fit、landscapeのみ）
   *
   * sourceを拡大・縮小せずに16:9のCanvasの中央へ描き、
   * 左右に黒い余白を追加する。
   *
   * 余白は整数の画素数にし、左右で1画素の差が出る場合は右側を大きくする。
   * 失敗した場合は従来方式（sourceをそのまま推論）へ戻す。
   */
  createAspectFitInput(source) {
    try {
      const sourceWidth =
        source.width;

      const sourceHeight =
        source.height;

      const inputWidth =
        Math.round(
          sourceHeight * LANDSCAPE_ASPECT_RATIO
        );

      /*
       * すでに16:9以上に横長の場合は余白を追加しない。
       */
      if (inputWidth <= sourceWidth) {
        this.aspectFitLayout = null;
        return source;
      }

      const padLeft =
        Math.floor(
          (inputWidth - sourceWidth) / 2
        );

      const padRight =
        inputWidth - sourceWidth - padLeft;

      if (!this.aspectFitCanvas) {
        this.aspectFitCanvas =
          document.createElement("canvas");

        this.aspectFitContext =
          this.aspectFitCanvas.getContext("2d");
      }

      const canvas =
        this.aspectFitCanvas;

      const context =
        this.aspectFitContext;

      if (
        canvas.width !== inputWidth ||
        canvas.height !== sourceHeight
      ) {
        canvas.width = inputWidth;
        canvas.height = sourceHeight;
      }

      context.fillStyle = "#000";

      context.fillRect(
        0,
        0,
        inputWidth,
        sourceHeight
      );

      context.drawImage(
        source,
        padLeft,
        0,
        sourceWidth,
        sourceHeight
      );

      this.aspectFitLayout = {
        sourceWidth,
        sourceHeight,
        inputWidth,
        inputHeight: sourceHeight,
        padLeft,
        padRight
      };

      return canvas;
    } catch (error) {
      this.disableAspectFit(
        "推論用画像を作成できませんでした",
        error
      );

      return source;
    }
  }

  /*
   * デバッグ用（?vb_debug=1&vb_aspect=fit）
   *
   * 余白付きの画像に対するマスクから、
   * 左右の余白の列を除いて元の推論用画像の大きさに戻す。
   *
   * MediaPipeは入力画像と同じ大きさのマスクを返すため、
   * 列の位置はそのまま元の画像の画素に対応する。
   */
  cropAspectFitMask(
    rawMask,
    rawWidth,
    rawHeight
  ) {
    const metrics =
      this.debugMetrics;

    const startedAt =
      metrics
        ? performance.now()
        : 0;

    const layout =
      this.aspectFitLayout;

    if (
      !layout ||
      rawWidth !== layout.inputWidth ||
      rawHeight !== layout.inputHeight ||
      rawMask.length !== rawWidth * rawHeight
    ) {
      const message =
        `マスクの大きさ（${rawWidth}x${rawHeight}）が推論用画像（${layout ? `${layout.inputWidth}x${layout.inputHeight}` : "-"}）と異なります`;

      this.disableAspectFit(message);

      throw new Error(
        `vb_aspect=fit: ${message}`
      );
    }

    const {
      sourceWidth,
      sourceHeight,
      inputWidth,
      padLeft
    } = layout;

    const pixelCount =
      sourceWidth * sourceHeight;

    if (
      !this.aspectFitMaskBuffer ||
      this.aspectFitMaskBuffer.length !==
        pixelCount
    ) {
      this.aspectFitMaskBuffer =
        new Float32Array(pixelCount);
    }

    const mask =
      this.aspectFitMaskBuffer;

    for (
      let y = 0;
      y < sourceHeight;
      y++
    ) {
      const rowStart =
        y * inputWidth + padLeft;

      mask.set(
        rawMask.subarray(
          rowStart,
          rowStart + sourceWidth
        ),
        y * sourceWidth
      );
    }

    if (metrics) {
      metrics.aspectCropMs +=
        performance.now() - startedAt;

      metrics.aspectCropFrames++;
    }

    return {
      mask,
      width: sourceWidth,
      height: sourceHeight
    };
  }

  /*
   * vb_aspect=fitを使えない場合は、
   * 以降のフレームを従来方式で推論する。
   */
  disableAspectFit(
    reason,
    error
  ) {
    if (this.aspectFitDisabled) {
      return;
    }

    this.aspectFitDisabled = true;
    this.aspectFitLayout = null;

    console.warn(
      `[vb_debug] vb_aspect=fit: ${reason}。従来方式（引き伸ばし）で推論します。`,
      ...(error ? [error] : [])
    );
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

    const layout =
      this.aspectFitLayout;

    if (
      layout &&
      segmentationInput === this.aspectFitCanvas
    ) {
      console.log(
        `[vb_debug] vb_aspect=fit 入力Canvas ${layout.inputWidth}x${layout.inputHeight}（元映像 ${layout.sourceWidth}x${layout.sourceHeight}）余白 左${layout.padLeft}px / 右${layout.padRight}px → マスクを${layout.sourceWidth}x${layout.sourceHeight}へ切り取り`
      );
    }

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
   * multiclassモデルの出力から
   * 人物の確信度マスクを作る（比較検証用）。
   *
   * personConfidence = 1 - backgroundConfidence
   *
   * 6チャンネルでない場合や、
   * マスクの大きさがそろっていない場合は例外にし、
   * 既存の推論失敗時の処理に任せる。
   *
   * 結果は再利用する配列へ書き込むため、
   * result.close()後も参照できる。
   */
  createMulticlassPersonMask(confidenceMasks, now) {
    if (
      confidenceMasks.length !==
      MULTICLASS_CATEGORIES.length
    ) {
      throw new Error(
        `multiclassの出力が${confidenceMasks.length}チャンネルです（${MULTICLASS_CATEGORIES.length}チャンネルが必要）`
      );
    }

    const backgroundMask =
      confidenceMasks[MULTICLASS_BACKGROUND_INDEX];

    const maskWidth =
      backgroundMask.width;

    const maskHeight =
      backgroundMask.height;

    const hasSameSize =
      confidenceMasks.every((categoryMask) =>
        categoryMask.width === maskWidth &&
        categoryMask.height === maskHeight
      );

    if (!hasSameSize) {
      throw new Error(
        "multiclassのマスクの大きさがそろっていません"
      );
    }

    /*
     * デバッグ時だけ内訳を計測する。
     * GPUの場合、最初の読み出しでGPUの処理完了を待つ。
     */
    const metrics =
      this.debugMetrics;

    let timedAt =
      metrics
        ? performance.now()
        : 0;

    const background =
      backgroundMask.getAsFloat32Array();

    if (metrics) {
      const readAt =
        performance.now();

      metrics.readMs +=
        readAt - timedAt;

      timedAt = readAt;
    }

    const pixelCount =
      background.length;

    if (pixelCount !== maskWidth * maskHeight) {
      throw new Error(
        "multiclassのマスクの画素数が大きさと一致しません"
      );
    }

    if (
      !this.multiclassPersonBuffer ||
      this.multiclassPersonBuffer.length !==
        pixelCount
    ) {
      this.multiclassPersonBuffer =
        new Float32Array(pixelCount);
    }

    const personMask =
      this.multiclassPersonBuffer;

    let invalidPixels = 0;

    /*
     * othersを差し引く方式（others_half・no_others）の場合だけ
     * othersの確率を読み取る。
     */
    const othersWeight =
      MULTICLASS_PERSON_MODES[
        this.debugConfig.personMode
      ];

    if (metrics) {
      timedAt = performance.now();
    }

    const others =
      othersWeight > 0
        ? confidenceMasks[
          MULTICLASS_OTHERS_INDEX
        ].getAsFloat32Array()
        : null;

    if (metrics) {
      const readAt =
        performance.now();

      metrics.readMs +=
        readAt - timedAt;

      timedAt = readAt;
    }

    let invalidOthersPixels = 0;

    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      const backgroundConfidence =
        background[i];

      /*
       * NaNや0〜1の範囲外の値は
       * 0〜1に収めて使用する。
       * NaNは背景（人物0）として扱う。
       */
      if (
        !(backgroundConfidence >= 0 &&
          backgroundConfidence <= 1)
      ) {
        invalidPixels++;
      }

      let person =
        1 - backgroundConfidence;

      if (others) {
        const othersConfidence =
          others[i];

        /*
         * othersのNaNや範囲外の値は0〜1に収める。
         * NaNは0（差し引かない）として扱う。
         */
        if (
          !(othersConfidence >= 0 &&
            othersConfidence <= 1)
        ) {
          invalidOthersPixels++;
        }

        person -=
          othersWeight *
          (othersConfidence > 0
            ? Math.min(othersConfidence, 1)
            : 0);
      }

      personMask[i] =
        person >= 0
          ? Math.min(person, 1)
          : 0;
    }

    if (metrics) {
      const convertedAt =
        performance.now();

      metrics.convertMs +=
        convertedAt - timedAt;

      timedAt = convertedAt;
    }

    this.checkMulticlassOutput(
      confidenceMasks,
      pixelCount,
      maskWidth,
      maskHeight,
      invalidPixels,
      now,
      invalidOthersPixels
    );

    /*
     * 2秒ごとの確認（全チャンネルの読み出しと集計）は
     * 統計の時間として数える。
     */
    if (metrics) {
      metrics.statsMs +=
        performance.now() - timedAt;
    }

    return personMask;
  }

  /*
   * multiclassの出力を一定間隔で確認する（デバッグ表示用）。
   *
   * 6クラスの確率の合計と、
   * 最も確率が高いクラスの画素の割合を表示する。
   * 全チャンネルを読むのはこのときだけ。
   */
  checkMulticlassOutput(
    confidenceMasks,
    pixelCount,
    maskWidth,
    maskHeight,
    invalidPixels,
    now,
    invalidOthersPixels = 0
  ) {
    this.multiclassInvalidPixels =
      (this.multiclassInvalidPixels || 0) +
      invalidPixels;

    this.multiclassInvalidOthersPixels =
      (this.multiclassInvalidOthersPixels || 0) +
      invalidOthersPixels;

    if (
      this.multiclassCheckNextAt !== undefined &&
      now < this.multiclassCheckNextAt
    ) {
      return;
    }

    this.multiclassCheckNextAt =
      now + DEBUG_REPORT_INTERVAL_MS;

    const channels =
      confidenceMasks.map((categoryMask) =>
        categoryMask.getAsFloat32Array()
      );

    const winners =
      new Array(channels.length).fill(0);

    let sumTotal = 0;
    let sumMin = Infinity;
    let sumMax = -Infinity;
    let invalidSums = 0;

    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      let sum = 0;
      let bestIndex = 0;
      let bestValue = -Infinity;

      for (
        let c = 0;
        c < channels.length;
        c++
      ) {
        const value =
          channels[c][i];

        sum += value;

        if (value > bestValue) {
          bestValue = value;
          bestIndex = c;
        }
      }

      if (!Number.isFinite(sum)) {
        invalidSums++;
        continue;
      }

      sumTotal += sum;
      sumMin = Math.min(sumMin, sum);
      sumMax = Math.max(sumMax, sum);
      winners[bestIndex]++;
    }

    const validPixels =
      pixelCount - invalidSums;

    const categoryShare = {};

    MULTICLASS_CATEGORIES.forEach((name, index) => {
      categoryShare[name] =
        `${((winners[index] / pixelCount) * 100).toFixed(1)}%`;
    });

    console.log(
      "[vb_debug] multiclass確認",
      {
        channels:
          confidenceMasks.length,
        size:
          `${maskWidth}x${maskHeight}`,
        probabilitySum:
          validPixels > 0
            ? {
              mean:
                Number((sumTotal / validPixels).toFixed(4)),
              min:
                Number(sumMin.toFixed(4)),
              max:
                Number(sumMax.toFixed(4))
            }
            : "計算できません",
        invalidSumPixels:
          invalidSums,
        invalidBackgroundPixels:
          this.multiclassInvalidPixels,
        ...(this.debugConfig.personMode !==
          DEFAULT_MULTICLASS_PERSON_MODE
          ? {
            person:
              this.debugConfig.personMode,
            invalidOthersPixels:
              this.multiclassInvalidOthersPixels
          }
          : {}),
        categoryShare
      }
    );

    this.multiclassInvalidPixels = 0;
    this.multiclassInvalidOthersPixels = 0;
  }

  /*
   * デバッグログ用に、使用中の人物マスクの計算式を返す。
   */
  describeMulticlassPersonMode() {
    const othersWeight =
      MULTICLASS_PERSON_MODES[
        this.debugConfig.personMode
      ];

    const background =
      MULTICLASS_CATEGORIES[
        MULTICLASS_BACKGROUND_INDEX
      ];

    const others =
      MULTICLASS_CATEGORIES[
        MULTICLASS_OTHERS_INDEX
      ];

    if (othersWeight === 0) {
      return `人物 = 1 - ${background}`;
    }

    if (othersWeight === 1) {
      return `人物 = 1 - ${background} - ${others}`;
    }

    return `人物 = 1 - ${background} - ${others} × ${othersWeight}`;
  }

  /*
   * 2段階しきい値方式（比較検証用）
   *
   * ?vb_debug=1&vb_mask=hysteresis の場合だけ使用する。
   *
   * 時間的平滑化はcreateRefinedMaskと同じ計算を行い、
   * 平滑化後の確信度に対して人物状態を判定する。
   *
   * 人物状態でない画素：
   *   現在の方式と同じ透明度（新たに背景を表示しない）。
   *
   * 人物状態の画素：
   *   EXIT〜KEEPの範囲で透明度を計算し、
   *   確信度が少し下がっても表示を維持する。
   */
  createHysteresisMask(mask, now) {
    const {
      alphaLow,
      alphaHigh,
      smoothing,
      hysteresisEnter: enter,
      hysteresisKeep: keep,
      hysteresisExit: exit,
      hysteresisHoldMs: holdMs,
      hysteresisEnterTimeoutMs: enterTimeoutMs
    } = this.debugConfig;

    const pixelCount =
      mask.length;

    /*
     * 推論が一定時間途切れた場合は、
     * 古い人物状態を使わない。
     */
    if (
      this.hysteresisLastUpdateAt !== null &&
      now - this.hysteresisLastUpdateAt >
        MASK_HOLD_MS
    ) {
      this.resetHysteresisState();
    }

    if (
      !this.hysteresisState ||
      this.hysteresisState.length !== pixelCount
    ) {
      this.hysteresisState =
        new Uint8Array(pixelCount);

      this.hysteresisConfirmedAt =
        new Float32Array(pixelCount);

      this.hysteresisEnteredAt =
        new Float32Array(pixelCount);

      this.hysteresisRetainedFlags =
        new Uint8Array(pixelCount);

      this.hysteresisEpoch = now;
    }

    this.hysteresisLastUpdateAt = now;

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

    const stableMask =
      this.previousStableMask;

    const refinedMask =
      this.refinedMaskBuffer;

    const states =
      this.hysteresisState;

    const confirmedAt =
      this.hysteresisConfirmedAt;

    const enteredAt =
      this.hysteresisEnteredAt;

    const retainedFlags =
      this.hysteresisRetainedFlags;

    const smoothingWeight =
      smoothing
        ? MASK_SMOOTHING_WEIGHT
        : 0;

    /*
     * Float32Arrayの精度を保つため、
     * 状態作成時からの経過時間で記録する。
     */
    const time =
      now - this.hysteresisEpoch;

    let retainedPixels = 0;
    let releasedByHold = 0;
    let releasedByTimeout = 0;

    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      const current =
        mask[i];

      const previous =
        stableMask[i];

      const stable =
        isFirstFrame ||
        Math.abs(current - previous) >
          MASK_MOTION_DIFF
          ? current
          : current * (1 - smoothingWeight) +
            previous * smoothingWeight;

      stableMask[i] =
        stable;

      let state =
        states[i];

      if (stable >= enter) {
        /*
         * ENTER以上：人物状態にする。
         */
        state = 1;
        confirmedAt[i] = time;
        enteredAt[i] = time;
      } else if (state === 1) {
        if (stable < exit) {
          /*
           * EXIT未満：すぐに解除。
           */
          state = 0;
        } else if (stable >= keep) {
          /*
           * KEEP以上：維持。
           */
          confirmedAt[i] = time;
        } else if (
          time - confirmedAt[i] >
          holdMs
        ) {
          /*
           * KEEP未満がHOLD時間を超えた：解除。
           */
          state = 0;
          releasedByHold++;
        }

        /*
         * ENTER以上が一定時間確認されない場合は
         * KEEP以上でも解除する（有効時のみ）。
         */
        if (
          state === 1 &&
          enterTimeoutMs > 0 &&
          time - enteredAt[i] >
            enterTimeoutMs
        ) {
          state = 0;
          releasedByTimeout++;
        }
      }

      states[i] =
        state;

      const normalAlpha =
        smoothstep(
          alphaLow,
          alphaHigh,
          stable
        );

      let alpha =
        normalAlpha;

      if (state === 1) {
        const heldAlpha =
          smoothstep(
            exit,
            keep,
            stable
          );

        if (heldAlpha > alpha) {
          alpha = heldAlpha;
        }
      }

      refinedMask[i] =
        alpha;

      if (
        alpha >
        normalAlpha +
          HYSTERESIS_RETAINED_ALPHA_DIFF
      ) {
        retainedFlags[i] = 1;
        retainedPixels++;
      } else {
        retainedFlags[i] = 0;
      }
    }

    if (this.debugMaskStats) {
      this.debugMaskStats.retainedPixels =
        retainedPixels;

      this.debugMaskStats.releasedByHold +=
        releasedByHold;

      this.debugMaskStats.releasedByTimeout +=
        releasedByTimeout;
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
      aspectFit: false,
      delegate: DEFAULT_SEGMENTATION_DELEGATE,
      view: null,
      classIndex: null,
      personMode: DEFAULT_MULTICLASS_PERSON_MODE,
      pose: false,
      modnetSize: MODNET_DEFAULT_SIZE,
      modnetPost: "raw",
      smoothing: true,
      alphaLow: MASK_ALPHA_LOW,
      alphaHigh: MASK_ALPHA_HIGH,
      edgeBlurPx: MASK_EDGE_BLUR_PX,
      maskMode: "current",
      hysteresisEnter: HYSTERESIS_ENTER,
      hysteresisKeep: HYSTERESIS_KEEP,
      hysteresisExit: HYSTERESIS_EXIT,
      hysteresisHoldMs: HYSTERESIS_HOLD_MS,
      hysteresisEnterTimeoutMs: HYSTERESIS_ENTER_TIMEOUT_MS,
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
        ) ||
        model === MODNET_MODEL
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

    /*
     * 推論用画像の縦横比（landscapeのみ）。
     * 未指定の場合は従来どおり引き伸ばす。
     */
    const aspect =
      params.get("vb_aspect");

    if (aspect !== null) {
      if (aspect !== "fit") {
        config.warnings.push(
          `vb_aspect=${aspect} は無効です（fit）。従来どおり推論します。`
        );
      } else if (config.model !== DEFAULT_SEGMENTATION_MODEL) {
        config.warnings.push(
          `vb_aspect=fit はvb_model=${DEFAULT_SEGMENTATION_MODEL}のときだけ使えます。指定を無視します。`
        );
      } else {
        config.aspectFit = true;
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
      } else if (view === DEBUG_CLASS_VIEW) {
        if (config.model === MULTICLASS_MODEL) {
          config.view = view;
        } else {
          config.warnings.push(
            `vb_view=${view} はvb_model=${MULTICLASS_MODEL}のときだけ使えます。デバッグ表示を行いません。`
          );
        }
      } else {
        config.warnings.push(
          `vb_view=${view} は無効です。デバッグ表示を行いません。`
        );
      }
    }

    /*
     * クラス別表示で、1つのクラスの確率を白黒表示する。
     * 未指定の場合は最大確率クラスを色分け表示する。
     */
    const classParam =
      params.get("vb_class");

    if (classParam !== null) {
      const classIndex =
        MULTICLASS_CATEGORIES.indexOf(classParam);

      if (config.view !== DEBUG_CLASS_VIEW) {
        config.warnings.push(
          `vb_class=${classParam} はvb_view=${DEBUG_CLASS_VIEW}（vb_model=${MULTICLASS_MODEL}）のときだけ使えます。指定を無視します。`
        );
      } else if (classIndex === -1) {
        config.warnings.push(
          `vb_class=${classParam} は無効です（${MULTICLASS_CATEGORIES.join("、")}）。最大確率クラスの色分けを表示します。`
        );
      } else {
        config.classIndex = classIndex;
      }
    }

    /*
     * multiclassの人物マスクの計算方法。
     * landscape・squareでは使用しない。
     */
    const personMode =
      params.get("vb_person");

    if (personMode !== null) {
      if (config.model !== MULTICLASS_MODEL) {
        config.warnings.push(
          `vb_person=${personMode} はvb_model=${MULTICLASS_MODEL}のときだけ使えます。指定を無視します。`
        );
      } else if (
        Object.prototype.hasOwnProperty.call(
          MULTICLASS_PERSON_MODES,
          personMode
        )
      ) {
        config.personMode = personMode;
      } else {
        config.warnings.push(
          `vb_person=${personMode} は無効です（${Object.keys(MULTICLASS_PERSON_MODES).join("、")}）。${DEFAULT_MULTICLASS_PERSON_MODE}を使用します。`
        );
      }
    }

    /*
     * MODNetの入力の短辺と後処理（vb_model=modnetのときだけ）。
     *
     * raw：MODNetの透明度をそのまま使う（既定）。
     * refine：既存のしきい値・平滑化（vb_maskも含む）を通す。
     */
    const modnetSize =
      params.get("vb_modnet_size");

    const modnetPost =
      params.get("vb_modnet_post");

    if (config.model === MODNET_MODEL) {
      if (modnetSize !== null) {
        if (
          MODNET_SIZES.map(String).includes(modnetSize)
        ) {
          config.modnetSize = Number(modnetSize);
        } else {
          config.warnings.push(
            `vb_modnet_size=${modnetSize} は無効です（${MODNET_SIZES.join("、")}）。${MODNET_DEFAULT_SIZE}を使用します。`
          );
        }
      }

      if (modnetPost !== null) {
        if (
          modnetPost === "raw" ||
          modnetPost === "refine"
        ) {
          config.modnetPost = modnetPost;
        } else {
          config.warnings.push(
            `vb_modnet_post=${modnetPost} は無効です（raw、refine）。rawを使用します。`
          );
        }
      }

      if (params.get("vb_pose") === "1") {
        config.warnings.push(
          "vb_pose=1 はvb_model=modnetでは使えません（MediaPipeへ戻った場合だけ使用します）。"
        );
      }
    } else if (
      modnetSize !== null ||
      modnetPost !== null
    ) {
      config.warnings.push(
        `vb_modnet_size・vb_modnet_post はvb_model=${MODNET_MODEL}のときだけ使えます。指定を無視します。`
      );
    }

    /*
     * 骨格の確認（Pose Landmarker）。
     * 人物マスクには使用しない。
     */
    const pose =
      params.get("vb_pose");

    if (pose === "1") {
      config.pose = true;
    } else if (
      pose !== null &&
      pose !== "0"
    ) {
      config.warnings.push(
        `vb_pose=${pose} は無効です（1、0）。骨格を表示しません。`
      );
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

    this.parseHysteresisParams(
      params,
      config
    );

    return config;
  }

  /*
   * 2段階しきい値方式のパラメータを読み取る。
   */
  parseHysteresisParams(params, config) {
    const mode =
      params.get("vb_mask");

    if (mode === "hysteresis") {
      config.maskMode = "hysteresis";
    } else if (
      mode !== null &&
      mode !== "current"
    ) {
      config.warnings.push(
        `vb_mask=${mode} は無効です。現在の方式（current）を使用します。`
      );
    }

    const enter =
      this.parseDebugNumberParam(
        params,
        "vb_enter",
        0,
        1,
        HYSTERESIS_ENTER,
        config.warnings
      );

    const keep =
      this.parseDebugNumberParam(
        params,
        "vb_keep",
        0,
        1,
        HYSTERESIS_KEEP,
        config.warnings
      );

    const exit =
      this.parseDebugNumberParam(
        params,
        "vb_exit",
        0,
        1,
        HYSTERESIS_EXIT,
        config.warnings
      );

    /*
     * EXIT < KEEP < ENTER を満たさない場合は
     * 3つとも既定値を使用する。
     */
    if (exit < keep && keep < enter) {
      config.hysteresisEnter = enter;
      config.hysteresisKeep = keep;
      config.hysteresisExit = exit;
    } else {
      config.warnings.push(
        `vb_exit=${exit} < vb_keep=${keep} < vb_enter=${enter} を満たさないため、既定値（${HYSTERESIS_EXIT} / ${HYSTERESIS_KEEP} / ${HYSTERESIS_ENTER}）を使用します。`
      );
    }

    config.hysteresisHoldMs =
      this.parseDebugNumberParam(
        params,
        "vb_hold",
        0,
        HYSTERESIS_MAX_HOLD_MS,
        HYSTERESIS_HOLD_MS,
        config.warnings
      );

    /*
     * 0は無効。
     * 有効にする場合は100〜10000ミリ秒。
     */
    const enterTimeout =
      this.parseDebugNumberParam(
        params,
        "vb_enter_timeout",
        0,
        HYSTERESIS_MAX_ENTER_TIMEOUT_MS,
        HYSTERESIS_ENTER_TIMEOUT_MS,
        config.warnings
      );

    if (
      enterTimeout !== 0 &&
      enterTimeout < HYSTERESIS_MIN_ENTER_TIMEOUT_MS
    ) {
      config.warnings.push(
        `vb_enter_timeout=${enterTimeout} は無効です（0、または${HYSTERESIS_MIN_ENTER_TIMEOUT_MS}〜${HYSTERESIS_MAX_ENTER_TIMEOUT_MS}）。時間制限を無効にします。`
      );
    } else {
      config.hysteresisEnterTimeoutMs =
        enterTimeout;
    }
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
        aspect:
          config.aspectFit
            ? "fit"
            : "従来（引き伸ばし）",
        delegate: config.delegate,
        view: config.view || "なし",
        ...(config.view === DEBUG_CLASS_VIEW
          ? {
            class:
              config.classIndex === null
                ? "最大確率クラス"
                : MULTICLASS_CATEGORIES[config.classIndex]
          }
          : {}),
        ...(config.model === MULTICLASS_MODEL
          ? {
            person: config.personMode
          }
          : {}),
        pose: config.pose,
        ...(config.model === MODNET_MODEL
          ? {
            modnetSize: config.modnetSize,
            modnetPost: config.modnetPost
          }
          : {}),
        smoothing: config.smoothing,
        alphaLow: config.alphaLow,
        alphaHigh: config.alphaHigh,
        edgeBlurPx: config.edgeBlurPx,
        mask: config.maskMode,
        ...(config.maskMode === "hysteresis"
          ? {
            enter: config.hysteresisEnter,
            keep: config.hysteresisKeep,
            exit: config.hysteresisExit,
            holdMs: config.hysteresisHoldMs,
            enterTimeoutMs:
              config.hysteresisEnterTimeoutMs || "無効"
          }
          : {})
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
      baseline: null,
      retainedPixels: 0,
      releasedByHold: 0,
      releasedByTimeout: 0
    };

    /*
     * 骨格の確認だけの場合も、
     * 骨格を重ねるデバッグ用Canvasを作成する。
     */
    if (config.view || config.pose) {
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
      convertMs: 0,
      refineMs: 0,
      maskCanvasMs: 0,
      compositeMs: 0,
      statsMs: 0,
      aspectCropMs: 0,
      aspectCropFrames: 0,
      modnetFrames: 0,
      modnetMs: 0,
      modnetPreMs: 0,
      modnetPostMs: 0,
      poseFrames: 0,
      poseMs: 0,
      poseDetectedFrames: 0,
      poseFailedFrames: 0
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
        "赤・水色は輪郭ぼかしの影響を含まない推定表示です。" +
        (this.debugConfig.maskMode === "hysteresis"
          ? " / 紫=2段階しきい値で維持している部分（現在の方式なら透明寄りになる部分。他の色より優先）"
          : "")
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
        `人物確信度 ${perMask(metrics.convertMs)}ms / ` +
        `平滑化・しきい値 ${perMask(metrics.refineMs)}ms / ` +
        `マスクCanvas ${perMask(metrics.maskCanvasMs)}ms / ` +
        `切り抜き ${perMask(metrics.compositeMs)}ms / ` +
        `統計 ${perMask(metrics.statsMs)}ms / ` +
        (metrics.aspectCropFrames > 0
          ? `余白の切り取り ${(metrics.aspectCropMs / metrics.aspectCropFrames).toFixed(2)}ms / `
          : "") +
        `推論+読み出し ${(inferenceAverage + metrics.readMs / metrics.maskFrames).toFixed(2)}ms`
      );
    }

    if (this.debugConfig.model === MODNET_MODEL) {
      this.reportModnetMetrics(
        metrics,
        elapsed
      );
    }

    if (this.debugConfig.pose) {
      this.reportPoseMetrics(metrics);
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
          summary.edgeMeanChange,
        ...(this.debugConfig.maskMode === "hysteresis"
          ? {
            retainedPixels:
              stats.retainedPixels,
            releasedByHold:
              stats.releasedByHold,
            releasedByTimeout:
              stats.releasedByTimeout
          }
          : {})
      }
    );

    stats.releasedByHold = 0;
    stats.releasedByTimeout = 0;
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
    maskHeight,
    confidenceMasks,
    frameSource = this.frameCanvas
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

    /*
     * vb_poseだけの場合は、
     * 推論に使ったカメラフレームを表示する（骨格は後で重ねる）。
     */
    if (!view) {
      context.drawImage(
        frameSource,
        0,
        0,
        maskWidth,
        maskHeight
      );

      return;
    }

    if (view === DEBUG_CLASS_VIEW) {
      this.drawClassView(
        confidenceMasks,
        maskWidth,
        maskHeight
      );

      return;
    }

    let imageData;

    if (view === "edge") {
      /*
       * 推論に使ったカメラフレームを
       * マスクと同じ大きさで描画する。
       */
      context.drawImage(
        frameSource,
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

    const retainedFlags =
      this.debugConfig.maskMode === "hysteresis" &&
      this.hysteresisRetainedFlags &&
      this.hysteresisRetainedFlags.length === mask.length
        ? this.hysteresisRetainedFlags
        : null;

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

      if (
        retainedFlags &&
        retainedFlags[i] === 1
      ) {
        /*
         * 紫：2段階しきい値で維持している部分
         */
        color = [200, 0, 255];
      } else if (alpha >= 0.1 && confidence < 0.5) {
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
        "水色: 人物が欠ける可能性（推定）",
        ...(retainedFlags
          ? ["紫: 2段階しきい値で維持（現方式なら透明寄り）"]
          : [])
      ]);
    } else {
      this.drawDebugLegend([
        view === "confidence"
          ? "confidence: 元の確信度（白=人物 / 黒=背景）"
          : "alpha: 最終的な透明度（白=不透明 / 黒=透明、ぼかし前）"
      ]);
    }
  }

  /*
   * デバッグ用（?vb_debug=1&vb_model=multiclass&vb_view=class）
   *
   * MediaPipeから返された6つのconfidenceMasksを読み、
   * 最大確率クラスの色分け、または
   * vb_classで指定したクラスの確率（白=1 / 黒=0）を表示する。
   *
   * 人物マスクと背景合成には使用しない。
   * result.close()より前に呼び出す。
   */
  drawClassView(
    confidenceMasks,
    maskWidth,
    maskHeight
  ) {
    const context =
      this.debugContext;

    const pixelCount =
      maskWidth * maskHeight;

    const channels =
      confidenceMasks.map((categoryMask) =>
        categoryMask.getAsFloat32Array()
      );

    if (
      !this.debugClassImageData ||
      this.debugClassImageData.width !== maskWidth ||
      this.debugClassImageData.height !== maskHeight
    ) {
      this.debugClassImageData =
        context.createImageData(
          maskWidth,
          maskHeight
        );
    }

    const imageData =
      this.debugClassImageData;

    const pixels =
      imageData.data;

    const classIndex =
      this.debugConfig.classIndex;

    if (classIndex !== null) {
      const channel =
        channels[classIndex];

      for (
        let i = 0;
        i < pixelCount;
        i++
      ) {
        const value =
          channel[i];

        /*
         * NaNは黒（0）として表示する。
         */
        const gray =
          value > 0
            ? Math.min(
              255,
              Math.round(value * 255)
            )
            : 0;

        const index =
          i * 4;

        pixels[index] = gray;
        pixels[index + 1] = gray;
        pixels[index + 2] = gray;
        pixels[index + 3] = 255;
      }
    } else {
      for (
        let i = 0;
        i < pixelCount;
        i++
      ) {
        /*
         * 6クラスを比較し、最も確率が高いクラスを選ぶ。
         * NaNは比較の対象にしない（全クラスNaNなら黒）。
         */
        let bestIndex = -1;
        let bestValue = -Infinity;

        for (
          let c = 0;
          c < channels.length;
          c++
        ) {
          const value =
            channels[c][i];

          if (value > bestValue) {
            bestValue = value;
            bestIndex = c;
          }
        }

        const color =
          bestIndex >= 0
            ? MULTICLASS_CLASS_COLORS[bestIndex]
            : [0, 0, 0];

        const index =
          i * 4;

        pixels[index] = color[0];
        pixels[index + 1] = color[1];
        pixels[index + 2] = color[2];
        pixels[index + 3] = 255;
      }
    }

    context.putImageData(
      imageData,
      0,
      0
    );

    if (classIndex !== null) {
      this.drawDebugLegend([
        `class: ${MULTICLASS_CATEGORIES[classIndex]}の確率（白=1 / 黒=0）`
      ]);
    } else {
      this.drawDebugLegend(
        MULTICLASS_CATEGORIES.map(
          (name, index) =>
            `${MULTICLASS_CLASS_COLOR_NAMES[index]}: ${name}`
        ),
        MULTICLASS_CLASS_COLORS
      );
    }
  }

  drawDebugLegend(lines, colors = null) {
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
      const top =
        fontSize * 0.3 + lineHeight * index;

      let left =
        fontSize * 0.4;

      /*
       * 色の指定がある場合は
       * 文字の前に色見本を描画する。
       */
      if (colors && colors[index]) {
        const [red, green, blue] =
          colors[index];

        context.fillStyle =
          `rgb(${red}, ${green}, ${blue})`;

        context.fillRect(
          left,
          top,
          fontSize,
          fontSize
        );

        context.fillStyle =
          "#fff";

        left += fontSize * 1.4;
      }

      context.fillText(
        line,
        left,
        top
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