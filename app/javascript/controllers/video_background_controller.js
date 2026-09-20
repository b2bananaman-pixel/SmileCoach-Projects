import { Controller } from "@hotwired/stimulus";
import {
  ImageSegmenter,
  FilesetResolver
} from "@mediapipe/tasks-vision";

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

    this.segmenter = null;
    this.isProcessing = false;

    /*
     * 前回のマスク
     *
     * 動きが少ないときのちらつきを
     * 抑えるために使用する。
     */
    this.previousStableMask = null;

    /*
     * 再利用するCanvas
     */
    this.personCanvas =
      document.createElement("canvas");

    this.personContext =
      this.personCanvas.getContext("2d");

    this.maskCanvas =
      document.createElement("canvas");

    this.maskContext =
      this.maskCanvas.getContext("2d");

    this.maskImageData = null;

    /*
     * 実際のカメラ比率
     */
    this.videoAspectRatio = 4 / 3;

    this.cameraReady = false;
    this.segmenterReady = false;

    this.setupCamera();
    this.setupSegmenter();
  }

  disconnect() {
    this.stopCamera();

    if (
      this.mediaRecorder &&
      this.mediaRecorder.state !== "inactive"
    ) {
      this.mediaRecorder.stop();
    }

    this.mediaRecorder = null;
    this.recordingStream = null;
    this.segmenter = null;

    this.previousStableMask = null;
    this.maskImageData = null;
  }

  async setupCamera() {
    try {
      this.mediaStream =
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

      this.sourceVideoTarget.srcObject =
        this.mediaStream;

      this.sourceVideoTarget.muted = true;
      this.sourceVideoTarget.playsInline = true;

      await this.sourceVideoTarget.play();

      const actualWidth =
        this.sourceVideoTarget.videoWidth;

      const actualHeight =
        this.sourceVideoTarget.videoHeight;

      console.log(
        "ImageSegmenterの準備が完了しました"
      );

      this.segmenterReady = true;
      this.updateRecordingReadyState();

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

      this.drawPreview();

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

      this.personCanvas.width =
        width;

      this.personCanvas.height =
        height;

      this.resetMaskHistory();
    }
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

  async setupSegmenter() {
    try {
      const vision =
        await FilesetResolver.forVisionTasks(
          "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@latest/wasm"
        );

      this.segmenter =
        await ImageSegmenter.createFromOptions(
          vision,
          {
            baseOptions: {
              modelAssetPath:
                "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter_landscape/float16/latest/selfie_segmenter_landscape.tflite"
            },

            runningMode: "VIDEO",

            outputConfidenceMasks: true,
            outputCategoryMask: false
          }
        );

      console.log(
        "ImageSegmenterの準備が完了しました"
      );

      this.segmenterReady = true;
      this.updateRecordingReadyState();
    } catch (error) {
      console.error(
        "ImageSegmenterの起動に失敗しました:",
        error
      );
    }
  }

  updateRecordingReadyState() {
    if (
      this.cameraReady &&
      this.segmenterReady
    ) {
      this.startButtonTarget.disabled = false;

      if (this.hasStatusTarget) {
        this.statusTarget.textContent =
          "録画前プレビュー";
      }
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
  }

  drawPreview() {
    if (!this.hasPreviewTarget) {
      return;
    }

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
      requestAnimationFrame(() =>
        this.drawPreview()
      );

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

    requestAnimationFrame(() =>
      this.drawPreview()
    );
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

    /*
     * 前回の処理中なら
     * 今回は無理に追加処理しない。
     *
     * 次のフレームで最新映像を処理する。
     */
    if (this.isProcessing) {
      return;
    }

    this.isProcessing = true;

    try {
      const timestamp =
        performance.now();

      const result =
        this.segmenter.segmentForVideo(
          video,
          timestamp
        );

      if (
        !result.confidenceMasks ||
        result.confidenceMasks.length === 0
      ) {
        context.drawImage(
          video,
          0,
          0,
          width,
          height
        );

        return;
      }

      /*
       * Landscapeモデルの
       * confidence mask
       */
      const confidenceMask =
        result.confidenceMasks[0];

      const mask =
        confidenceMask.getAsFloat32Array();

      const maskWidth =
        confidenceMask.width;

      const maskHeight =
        confidenceMask.height;

      const refinedMask =
        this.createRefinedMask(
          mask,
          maskWidth,
          maskHeight
        );

      this.drawPersonFromMask(
        video,
        context,
        refinedMask,
        maskWidth,
        maskHeight,
        width,
        height
      );
    } catch (error) {
      console.error(
        "背景合成中にエラーが発生しました:",
        error
      );

      context.drawImage(
        video,
        0,
        0,
        width,
        height
      );
    } finally {
      this.isProcessing = false;
    }
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

  createRefinedMask(
    mask,
    width,
    height
  ) {
    /*
     * 背景と人物の境界を決める値。
     */
    const BACKGROUND_THRESHOLD =
      0.20;

    const PERSON_THRESHOLD =
      0.75;

    const pixelCount =
      mask.length;

    const currentMask =
      new Float32Array(
        pixelCount
      );

    /*
     * 基本マスク作成
     */
    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      const confidence =
        mask[i];

      if (
        confidence <=
        BACKGROUND_THRESHOLD
      ) {
        currentMask[i] = 0;
      } else if (
        confidence >=
        PERSON_THRESHOLD
      ) {
        currentMask[i] = 1;
      } else {
        currentMask[i] =
          (confidence -
            BACKGROUND_THRESHOLD) /
          (PERSON_THRESHOLD -
            BACKGROUND_THRESHOLD);
      }
    }

    /*
     * 初回
     */
    if (
      !this.previousStableMask ||
      this.previousStableMask.length !==
        pixelCount
    ) {
      this.previousStableMask =
        new Float32Array(
          currentMask
        );

      return this.applySpatialRefinement(
        currentMask,
        width,
        height
      );
    }

    const stableMask =
      new Float32Array(
        pixelCount
      );

    /*
     * フレーム間安定化
     *
     * 静止中は少し前フレームを利用。
     * 大きな動きは現在フレームを優先。
     */
    for (
      let i = 0;
      i < pixelCount;
      i++
    ) {
      const current =
        currentMask[i];

      const previous =
        this.previousStableMask[i];

      /*
       * 明確な人物
       *
       * すぐ追従。
       */
      if (
        current >=
        PERSON_THRESHOLD
      ) {
        stableMask[i] = 1;
        continue;
      }

      /*
       * 明確な背景
       *
       * 背景はちらつき防止のため
       * 少し前フレームを利用。
       */
      if (
        current <=
        BACKGROUND_THRESHOLD
      ) {
        stableMask[i] =
          previous * 0.20;

        if (
          stableMask[i] < 0.05
        ) {
          stableMask[i] = 0;
        }

        continue;
      }

      /*
       * 境界部分
       */
      const difference =
        Math.abs(
          current - previous
        );

      /*
       * 大きく変化したら
       * 現在フレームを即採用。
       *
       * → 動きへの追従を優先。
       */
      if (
        difference > 0.20
      ) {
        stableMask[i] =
          current;

        continue;
      }

      /*
       * 小さな変化だけ
       * 20%前フレームを残す。
       *
       * → 静止中のちらつきを抑える。
       */
      stableMask[i] =
        current * 0.80 +
        previous * 0.20;
    }

    this.previousStableMask =
      new Float32Array(
        stableMask
      );

    return this.applySpatialRefinement(
      stableMask,
      width,
      height
    );
  }

  applySpatialRefinement(
    mask,
    width,
    height
  ) {
    const result =
      new Float32Array(
        mask.length
      );

    /*
     * MediaPipeの低解像度マスクだけを
     * 処理する。
     */
    for (
      let y = 0;
      y < height;
      y++
    ) {
      for (
        let x = 0;
        x < width;
        x++
      ) {
        const index =
          y * width + x;

        const current =
          mask[index];

        /*
         * 画面端
         */
        if (
          x === 0 ||
          y === 0 ||
          x === width - 1 ||
          y === height - 1
        ) {
          result[index] =
            current;

          continue;
        }

        let personNeighbors = 0;
        let backgroundNeighbors = 0;

        /*
         * 3×3近傍
         */
        for (
          let dy = -1;
          dy <= 1;
          dy++
        ) {
          for (
            let dx = -1;
            dx <= 1;
            dx++
          ) {
            if (
              dx === 0 &&
              dy === 0
            ) {
              continue;
            }

            const neighborIndex =
              (y + dy) * width +
              (x + dx);

            const neighbor =
              mask[neighborIndex];

            if (
              neighbor >= 0.75
            ) {
              personNeighbors++;
            }

            if (
              neighbor <= 0.20
            ) {
              backgroundNeighbors++;
            }
          }
        }

        /*
         * 周囲が人物なら
         * 人物として残す。
         */
        if (
          personNeighbors >= 4
        ) {
          result[index] =
            Math.max(
              current,
              0.75
            );

          continue;
        }

        /*
         * 周囲が背景なら
         * 背景として除去。
         */
        if (
          backgroundNeighbors >= 6
        ) {
          result[index] =
            Math.min(
              current,
              0.05
            );

          continue;
        }

        /*
         * 境界
         */
        if (
          current >= 0.55
        ) {
          result[index] =
            0.60;
        } else {
          result[index] = 0;
        }
      }
    }

    return result;
  }

  drawPersonFromMask(
    video,
    context,
    mask,
    maskWidth,
    maskHeight,
    width,
    height
  ) {
    /*
     * 人物Canvasを再利用
     */
    const personCanvas =
      this.personCanvas;

    const personContext =
      this.personContext;

    personContext.globalCompositeOperation =
      "source-over";

    personContext.clearRect(
      0,
      0,
      width,
      height
    );

    /*
     * カメラ映像
     */
    personContext.drawImage(
      video,
      0,
      0,
      width,
      height
    );

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

    /*
     * 人物部分だけ残す
     */
    personContext.globalCompositeOperation =
      "destination-in";

    personContext.drawImage(
      this.maskCanvas,
      0,
      0,
      width,
      height
    );

    personContext.globalCompositeOperation =
      "source-over";

    /*
     * 背景の上に人物を描画
     */
    context.drawImage(
      personCanvas,
      0,
      0,
      width,
      height
    );
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
     * 音声
     */
    const audioTracks =
      this.mediaStream.getAudioTracks();

    audioTracks.forEach(
      (track) => {
        canvasStream.addTrack(track);
      }
    );

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
      () => {
        this.finishRecording();
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