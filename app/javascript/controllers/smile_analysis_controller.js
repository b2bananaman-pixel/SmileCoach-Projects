import { Controller } from "@hotwired/stimulus"
import { FaceLandmarker, FilesetResolver } from "@mediapipe/tasks-vision"

export default class extends Controller {
  static values = {
    speechSegments: Array,
    updateUrl: String
  }

  static POST_SPEECH_WINDOW = 0.5
  static ANALYSIS_INTERVAL = 0.2

  async connect() {
    console.log("Smile analysis controller connected")

    const video = this.element.querySelector("video")

    if (!video) {
      console.log("分析対象の動画がありません")
      return
    }

    try {
      const vision = await FilesetResolver.forVisionTasks(
        "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@1.0.1/wasm"
      )

      const faceLandmarker = await FaceLandmarker.createFromOptions(
        vision,
        {
          baseOptions: {
            modelAssetPath:
              "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
          },
          outputFaceBlendshapes: true,
          runningMode: "VIDEO"
        }
      )

      const analyzeVideo = () => {
        console.log("動画の読み込み完了")
        console.log("動画の長さ:", video.duration)
        console.log("話している区間:", this.speechSegmentsValue)

        if (!video.duration || !Number.isFinite(video.duration)) {
          console.log("動画の長さを取得できませんでした")
          return
        }

        if (this.speechSegmentsValue.length === 0) {
          console.log("話している区間がありません")
          return
        }

        const duration = video.duration
        const interval = this.constructor.ANALYSIS_INTERVAL
        const postSpeechWindow = this.constructor.POST_SPEECH_WINDOW

        let segmentIndex = 0
        let currentTime = this.speechSegmentsValue[0].start
        let frameCount = 0

        const smileSamples = []

        const analyzeFrame = () => {
          if (segmentIndex >= this.speechSegmentsValue.length) {
            this.displaySmileSummary(smileSamples)

            console.log("話している区間の解析が完了しました")
            console.log("解析フレーム数:", frameCount)

            return
          }

          if (currentTime >= duration) {
            this.displaySmileSummary(smileSamples)

            console.log(
              "動画終了時刻に到達したため解析を終了しました"
            )
            console.log("解析フレーム数:", frameCount)

            return
          }

          const segment = this.speechSegmentsValue[segmentIndex]

          const segmentEnd = Math.min(
            segment.end + postSpeechWindow,
            duration
          )

          if (currentTime < segment.start) {
            currentTime = segment.start
          }

          if (currentTime >= segmentEnd) {
            segmentIndex += 1

            if (segmentIndex < this.speechSegmentsValue.length) {
              currentTime =
                this.speechSegmentsValue[segmentIndex].start
            }

            analyzeFrame()

            return
          }

          const analysisTime = Math.min(
            currentTime,
            duration - 0.001
          )

          video.currentTime = analysisTime

          const handleSeeked = () => {
            const result = faceLandmarker.detectForVideo(
              video,
              performance.now()
            )

            frameCount += 1

            if (result.faceBlendshapes?.length > 0) {
              const categories =
                result.faceBlendshapes[0].categories

              const mouthSmileLeft = categories.find(
                (category) =>
                  category.categoryName === "mouthSmileLeft"
              )

              const mouthSmileRight = categories.find(
                (category) =>
                  category.categoryName === "mouthSmileRight"
              )

              const leftScore =
                mouthSmileLeft?.score ?? 0

              const rightScore =
                mouthSmileRight?.score ?? 0

              const smileStrength =
                (leftScore + rightScore) / 2

              smileSamples.push({
                time: video.currentTime,
                left: leftScore,
                right: rightScore,
                strength: smileStrength
              })

              console.log(
                `解析結果 ${frameCount}:`,
                `区間=${segmentIndex + 1}`,
                `時間=${video.currentTime.toFixed(2)}秒`,
                `mouthSmileLeft=${leftScore}`,
                `mouthSmileRight=${rightScore}`,
                `笑顔強度=${smileStrength}`
              )
            } else {
              console.log(
                `解析結果 ${frameCount}:`,
                `区間=${segmentIndex + 1}`,
                `時間=${video.currentTime.toFixed(2)}秒`,
                "顔が検出されませんでした"
              )
            }

            currentTime += interval

            analyzeFrame()
          }

          video.addEventListener(
            "seeked",
            handleSeeked,
            { once: true }
          )
        }

        analyzeFrame()
      }

      if (video.readyState >= 2) {
        analyzeVideo()
      } else {
        video.addEventListener(
          "loadeddata",
          analyzeVideo,
          { once: true }
        )
      }
    } catch (error) {
      console.error(
        "笑顔分析の初期化に失敗しました:",
        error
      )
    }
  }

  displaySmileSummary(smileSamples) {
    if (smileSamples.length === 0) {
      console.log(
        "笑顔を解析できるフレームがありませんでした"
      )

      this.saveSmileScore(null)

      return
    }

    const strengths = smileSamples.map(
      (sample) => sample.strength
    )

    const averageSmile =
      strengths.reduce(
        (total, value) => total + value,
        0
      ) / strengths.length

    const maxSmile = Math.max(...strengths)

    // 0.2以上を「明確な笑顔」として補助的に判定する
    const smileThreshold = 0.2

    const smilingFrameCount =
      strengths.filter(
        (value) => value >= smileThreshold
      ).length

    const smileRate =
      smilingFrameCount / strengths.length

    const smileRatePercent =
      smileRate * 100

    // 平均笑顔強度を中心に100点満点で評価する
    //
    // 0.00 → 40点
    // 0.02 → 60点
    // 0.05 → 70点
    // 0.10 → 80点
    // 0.15 → 87点
    // 0.20 → 92点
    // 0.25 → 95点
    // 0.30 → 98点
    // 0.35以上 → 100点

    let smileScore

    if (averageSmile <= 0.02) {
      smileScore =
        40 +
        (averageSmile / 0.02) * 20
    } else if (averageSmile <= 0.05) {
      smileScore =
        60 +
        ((averageSmile - 0.02) / 0.03) * 10
    } else if (averageSmile <= 0.10) {
      smileScore =
        70 +
        ((averageSmile - 0.05) / 0.05) * 10
    } else if (averageSmile <= 0.15) {
      smileScore =
        80 +
        ((averageSmile - 0.10) / 0.05) * 7
    } else if (averageSmile <= 0.20) {
      smileScore =
        87 +
        ((averageSmile - 0.15) / 0.05) * 5
    } else if (averageSmile <= 0.25) {
      smileScore =
        92 +
        ((averageSmile - 0.20) / 0.05) * 3
    } else if (averageSmile <= 0.30) {
      smileScore =
        95 +
        ((averageSmile - 0.25) / 0.05) * 3
    } else if (averageSmile <= 0.35) {
      smileScore =
        98 +
        ((averageSmile - 0.30) / 0.05) * 2
    } else {
      smileScore = 100
    }

    smileScore = Math.min(
      100,
      Math.round(smileScore)
    )

    console.log(
      "========== 笑顔分析結果 =========="
    )

    console.log(
      "話している区間数:",
      this.speechSegmentsValue.length
    )

    console.log(
      "解析フレーム数:",
      smileSamples.length
    )

    console.log(
      "平均笑顔強度:",
      averageSmile
    )

    console.log(
      "最大笑顔強度:",
      maxSmile
    )

    console.log(
      "笑顔判定フレーム数:",
      smilingFrameCount
    )

    console.log(
      "笑顔率:",
      smileRate
    )

    console.log(
      "笑顔率（％）:",
      `${smileRatePercent.toFixed(1)}%`
    )

    console.log(
      "笑顔スコア:",
      `${smileScore}点`
    )

    this.saveSmileScore(smileScore)

    console.log(
      "================================"
    )
  }

  async saveSmileScore(smileScore) {
    try {
      const response = await fetch(
        this.updateUrlValue,
        {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token":
              document.querySelector(
                'meta[name="csrf-token"]'
              )?.content,
            Accept: "application/json"
          },
          body: JSON.stringify({
            smile_score: smileScore
          })
        }
      )

      if (!response.ok) {
        throw new Error(
          `笑顔スコアの保存に失敗しました: ${response.status}`
        )
      }

      const data = await response.json()

      if (data.smile_score === null) {
        console.log(
          "笑顔スコアは保存せず、3項目平均の総合スコアを保存しました:",
          data.total_score
        )

        this.updateSmileAnalysisUnavailableDisplay()
      } else {
        console.log(
          "笑顔スコアを保存しました:",
          data.smile_score
        )

        console.log(
          "4項目平均の総合スコアを保存しました:",
          data.total_score
        )

        this.updateSmileScoreDisplay(data.smile_score)
      }

      this.updateTotalScoreDisplay(data.total_score)
    } catch (error) {
      console.error(
        "笑顔スコアの保存に失敗しました:",
        error
      )
    }
  }

  updateSmileScoreDisplay(smileScore) {
    const smileScoreElement =
      document.querySelector(
        "[data-smile-analysis-smile-score]"
      )

    const smileScoreUnitElement =
      document.querySelector(
        "[data-smile-analysis-smile-score-unit]"
      )

    const smileMessageElement =
      document.querySelector(
        "[data-smile-analysis-smile-message]"
      )

    if (!smileScoreElement) {
      console.log(
        "笑顔スコアの表示要素が見つかりませんでした"
      )

      return
    }

    smileScoreElement.textContent = smileScore

    if (smileScoreUnitElement) {
      smileScoreUnitElement.textContent = "点"
    }

    if (smileMessageElement) {
      smileMessageElement.textContent =
        "表情から笑顔を分析しました"
    }

    console.log(
      "画面の笑顔スコアを更新しました:",
      smileScore
    )
  }

  updateSmileAnalysisUnavailableDisplay() {
    const smileScoreElement =
      document.querySelector(
        "[data-smile-analysis-smile-score]"
      )

    const smileScoreUnitElement =
      document.querySelector(
        "[data-smile-analysis-smile-score-unit]"
      )

    const smileMessageElement =
      document.querySelector(
        "[data-smile-analysis-smile-message]"
      )

    if (smileScoreElement) {
      smileScoreElement.textContent =
        "分析できませんでした"
    }

    if (smileScoreUnitElement) {
      smileScoreUnitElement.textContent = ""
    }

    if (smileMessageElement) {
      smileMessageElement.textContent =
        "笑顔を分析できませんでした"
    }

    console.log(
      "笑顔分析ができなかったため、笑顔スコアを表示しませんでした"
    )
  }

  updateTotalScoreDisplay(totalScore) {
    const totalScoreElement =
      document.querySelector(
        "[data-smile-analysis-total-score]"
      )

    const totalScoreUnitElement =
      document.querySelector(
        "[data-smile-analysis-total-score-unit]"
      )

    if (!totalScoreElement) {
      console.log(
        "総合スコアの表示要素が見つかりませんでした"
      )

      return
    }

    totalScoreElement.textContent = totalScore

    if (totalScoreUnitElement) {
      totalScoreUnitElement.textContent = "点"
    }

    console.log(
      "画面の総合スコアを更新しました:",
      totalScore
    )
  }

}
