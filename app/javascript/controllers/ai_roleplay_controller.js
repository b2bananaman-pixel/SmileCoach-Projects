import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "status",
    "stopTurnButton",
    "transcription",
    "aiReply",
    "customerState",
    "timer",
    "preparation",
    "countdown",
    "countdownNumber",
    "preview",
    "recordingIndicator",
    "customerExpression",
    "turnMessage",
    "endRoleplayButton"
  ]

  static values = {
    transcribeUrl: String,
    respondUrl: String,
    synthesizeUrl: String
  }

  connect() {
    this.mediaStream = null
    this.roleplayRecorder = null
    this.roleplayChunks = []

    this.turnRecorder = null
    this.turnChunks = []

    this.countdownTimer = null
    this.roleplayTimer = null

    this.remainingSeconds = 10 * 60
    this.roleplayStarted = false
    this.roleplayEnded = false

    this.turnProcessing = false
    this.conversationHistory = []

    this.prepareRoleplay()
  }

  disconnect() {
    this.roleplayEnded = true

    this.clearCountdownTimer()
    this.clearRoleplayTimer()
    this.stopMediaStream()
  }

  async prepareRoleplay() {
    try {
      this.setStatus(
        "カメラとマイクを準備しています..."
      )

      if (this.hasPreparationTarget) {
        this.preparationTarget.textContent =
          "カメラとマイクを準備しています..."
      }

      this.mediaStream =
        await navigator.mediaDevices.getUserMedia({
          video: true,
          audio: true
        })

      if (this.hasPreviewTarget) {
        this.previewTarget.srcObject =
          this.mediaStream

        await this.previewTarget.play()
      }

      if (this.hasPreparationTarget) {
        this.preparationTarget.textContent =
          "カメラとマイクの準備ができました"
      }

      this.setStatus(
        "まもなくロープレを開始します"
      )

      await this.startCountdown()
    } catch (error) {
      console.error(error)

      this.setStatus(
        "カメラまたはマイクを使用できません"
      )

      if (this.hasPreparationTarget) {
        this.preparationTarget.classList.remove(
          "alert-info"
        )

        this.preparationTarget.classList.add(
          "alert-danger"
        )

        this.preparationTarget.textContent =
          "カメラまたはマイクを使用できません。ブラウザの権限設定を確認してください。"
      }

      if (this.hasTurnMessageTarget) {
        this.turnMessageTarget.textContent =
          "ロープレを開始できません"
      }
    }
  }

  startCountdown() {
    return new Promise((resolve) => {
      if (this.hasCountdownTarget) {
        this.countdownTarget.classList.remove(
          "d-none"
        )
      }

      if (this.hasPreparationTarget) {
        this.preparationTarget.classList.add(
          "d-none"
        )
      }

      let count = 3

      this.updateCountdownNumber(count)

      this.countdownTimer =
        window.setInterval(() => {
          count -= 1

          if (count > 0) {
            this.updateCountdownNumber(count)
            return
          }

          this.clearCountdownTimer()

          if (this.hasCountdownTarget) {
            this.countdownTarget.classList.add(
              "d-none"
            )
          }

          this.startRoleplay()
          resolve()
        }, 1000)
    })
  }

  updateCountdownNumber(number) {
    if (this.hasCountdownNumberTarget) {
      this.countdownNumberTarget.textContent =
        number
    }
  }

  startRoleplay() {
    if (
      this.roleplayStarted ||
      this.roleplayEnded ||
      !this.mediaStream
    ) {
      return
    }

    this.roleplayStarted = true

    this.startContinuousRecording()
    this.startRoleplayTimer()
    this.startTurnRecording()

    this.setClerkTurnState()

    if (this.hasEndRoleplayButtonTarget) {
      this.endRoleplayButtonTarget.disabled =
        false
    }

    if (this.hasRecordingIndicatorTarget) {
      this.recordingIndicatorTarget.classList.remove(
        "bg-secondary"
      )

      this.recordingIndicatorTarget.classList.add(
        "bg-danger"
      )

      this.recordingIndicatorTarget.textContent =
        "● 録画中"
    }
  }

  startContinuousRecording() {
    const mimeType =
      this.supportedVideoMimeType()

    const options = mimeType
      ? { mimeType: mimeType }
      : undefined

    this.roleplayChunks = []

    this.roleplayRecorder =
      new MediaRecorder(
        this.mediaStream,
        options
      )

    this.roleplayRecorder.addEventListener(
      "dataavailable",
      (event) => {
        if (event.data.size > 0) {
          this.roleplayChunks.push(
            event.data
          )
        }
      }
    )

    this.roleplayRecorder.addEventListener(
      "stop",
      () => {
        this.handleRoleplayRecordingStopped()
      },
      { once: true }
    )

    this.roleplayRecorder.start()
  }

  startTurnRecording() {
    if (
      !this.mediaStream ||
      this.roleplayEnded ||
      this.turnProcessing
    ) {
      return
    }

    if (
      this.turnRecorder &&
      this.turnRecorder.state === "recording"
    ) {
      return
    }

    const audioTracks =
      this.mediaStream.getAudioTracks()

    if (audioTracks.length === 0) {
      return
    }

    const audioStream =
      new MediaStream(audioTracks)

    const mimeType =
      this.supportedAudioMimeType()

    const options = mimeType
      ? { mimeType: mimeType }
      : undefined

    this.turnChunks = []

    this.turnRecorder =
      new MediaRecorder(
        audioStream,
        options
      )

    this.turnRecorder.addEventListener(
      "dataavailable",
      (event) => {
        if (event.data.size > 0) {
          this.turnChunks.push(
            event.data
          )
        }
      }
    )

    this.turnRecorder.start()
  }

  stopTurn() {
    if (
      this.roleplayEnded ||
      this.turnProcessing ||
      !this.turnRecorder ||
      this.turnRecorder.state !== "recording"
    ) {
      return
    }

    this.turnProcessing = true

    if (this.hasStopTurnButtonTarget) {
      this.stopTurnButtonTarget.disabled =
        true
    }

    this.setStatus(
      "発話を受け付けました"
    )

    if (this.hasTurnMessageTarget) {
      this.turnMessageTarget.textContent =
        "発話を受け付けました"
    }

    const recorder =
      this.turnRecorder

    recorder.addEventListener(
      "stop",
      () => {
        this.processTurn(recorder)
      },
      { once: true }
    )

    recorder.stop()
  }

  async processTurn(recorder) {
    try {
      if (this.roleplayEnded) {
        return
      }

      const mimeType =
        recorder?.mimeType ||
        this.supportedAudioMimeType() ||
        "audio/webm"

      const audioBlob =
        new Blob(
          this.turnChunks,
          { type: mimeType }
        )

      if (audioBlob.size === 0) {
        throw new Error(
          "録音データが空です"
        )
      }

      this.setStatus(
        "音声を文字起こししています..."
      )

      if (this.hasTurnMessageTarget) {
        this.turnMessageTarget.textContent =
          "店員の発話を確認しています..."
      }

      const transcription =
        await this.transcribe(audioBlob)

      if (this.roleplayEnded) {
        return
      }

      if (this.hasTranscriptionTarget) {
        this.transcriptionTarget.textContent =
          transcription
      }

      this.setStatus(
        "AI顧客が返答を考えています..."
      )

      if (this.hasTurnMessageTarget) {
        this.turnMessageTarget.textContent =
          "AI顧客が返答を考えています..."
      }

      const aiResponse =
        await this.createAiResponse(
          transcription
        )

      if (this.roleplayEnded) {
        return
      }

      if (this.hasAiReplyTarget) {
        this.aiReplyTarget.textContent =
          aiResponse.reply
      }

      if (this.hasCustomerStateTarget) {
        this.customerStateTarget.textContent =
          aiResponse.customer_state || "-"
      }

      this.updateCustomerExpression(
        aiResponse.customer_state
      )

      this.addConversationTurn(
        transcription,
        aiResponse.reply
      )

      this.setStatus(
        "AI顧客の音声を生成しています..."
      )

      if (this.hasTurnMessageTarget) {
        this.turnMessageTarget.textContent =
          "AI顧客が返答します"
      }

      const aiAudio =
        await this.synthesize(
          aiResponse.reply
        )

      if (this.roleplayEnded) {
        return
      }

      this.setStatus(
        "AI顧客が話しています..."
      )

      if (this.hasTurnMessageTarget) {
        this.turnMessageTarget.textContent =
          "AI顧客が話しています..."
      }

      await this.playAudio(aiAudio)

      if (this.roleplayEnded) {
        return
      }

      if (aiResponse.conversation_end) {
        this.finishConversation(
          aiResponse.end_reason
        )
        return
      }

      this.turnProcessing = false

      this.startTurnRecording()
      this.setClerkTurnState()
    } catch (error) {
      console.error(error)

      if (this.roleplayEnded) {
        return
      }

      this.turnProcessing = false

      this.setStatus(
        `AIロープレ処理に失敗しました: ${error.message}`
      )

      if (this.hasTurnMessageTarget) {
        this.turnMessageTarget.textContent =
          "処理に失敗しました。もう一度話してください。"
      }

      this.startTurnRecording()

      if (this.hasStopTurnButtonTarget) {
        this.stopTurnButtonTarget.disabled =
          false
      }
    }
  }

  addConversationTurn(
    clerkMessage,
    aiReply
  ) {
    this.conversationHistory.push(
      {
        role: "user",
        content: clerkMessage
      },
      {
        role: "assistant",
        content: aiReply
      }
    )
  }

  setClerkTurnState() {
    if (this.roleplayEnded) {
      return
    }

    this.setStatus("あなたの番です")

    if (this.hasTurnMessageTarget) {
      this.turnMessageTarget.textContent =
        "あなたの番です"
    }

    if (this.hasStopTurnButtonTarget) {
      this.stopTurnButtonTarget.disabled =
        false
    }
  }

  updateCustomerExpression(
    customerState
  ) {
    if (!this.hasCustomerExpressionTarget) {
      return
    }

    const labels = {
      neutral: "😐",
      interested: "🙂",
      concerned: "😟",
      satisfied: "😊"
    }

    this.customerExpressionTarget.textContent =
      labels[customerState] || "😐"
  }

  finishConversation(endReason) {
    if (this.roleplayEnded) {
      return
    }

    this.turnProcessing = false

    this.setStatus(
      endReason || "会話が終了しました"
    )

    if (this.hasTurnMessageTarget) {
      this.turnMessageTarget.textContent =
        endReason || "会話が終了しました"
    }

    this.finishRoleplay()
  }

  startRoleplayTimer() {
    this.remainingSeconds = 10 * 60
    this.updateTimer()

    this.roleplayTimer =
      window.setInterval(() => {
        if (
          this.roleplayEnded ||
          this.remainingSeconds <= 0
        ) {
          this.clearRoleplayTimer()
          return
        }

        this.remainingSeconds -= 1
        this.updateTimer()

        if (this.remainingSeconds === 0) {
          this.clearRoleplayTimer()
          this.finishRoleplay()
        }
      }, 1000)
  }

  updateTimer() {
    if (!this.hasTimerTarget) {
      return
    }

    const minutes =
      Math.floor(
        this.remainingSeconds / 60
      )

    const seconds =
      this.remainingSeconds % 60

    this.timerTarget.textContent =
      `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
  }

  endRoleplay() {
    if (
      !this.roleplayStarted ||
      this.roleplayEnded
    ) {
      return
    }

    const confirmed =
      window.confirm(
        "ロープレを終了しますか？\n終了すると分析を開始します。"
      )

    if (!confirmed) {
      return
    }

    this.finishRoleplay()
  }

  finishRoleplay() {
    if (this.roleplayEnded) {
      return
    }

    this.roleplayEnded = true
    this.turnProcessing = false

    this.clearCountdownTimer()
    this.clearRoleplayTimer()

    if (
      this.turnRecorder &&
      this.turnRecorder.state === "recording"
    ) {
      this.turnRecorder.stop()
    }

    if (
      this.roleplayRecorder &&
      this.roleplayRecorder.state === "recording"
    ) {
      this.roleplayRecorder.stop()
    }

    if (this.hasStopTurnButtonTarget) {
      this.stopTurnButtonTarget.disabled =
        true
    }

    if (this.hasEndRoleplayButtonTarget) {
      this.endRoleplayButtonTarget.disabled =
        true
    }

    if (this.hasRecordingIndicatorTarget) {
      this.recordingIndicatorTarget.classList.remove(
        "bg-danger"
      )

      this.recordingIndicatorTarget.classList.add(
        "bg-secondary"
      )

      this.recordingIndicatorTarget.textContent =
        "● 録画終了"
    }

    this.setStatus(
      "ロープレを終了しました"
    )

    if (this.hasTurnMessageTarget) {
      this.turnMessageTarget.textContent =
        "ロープレを終了しました"
    }
  }

  handleRoleplayRecordingStopped() {
    /*
     * 録画データの保存、AIロープレ内容分析、
     * 基本接客分析への受け渡しは後続Issueで実装する。
     */
    this.stopMediaStream()
  }

  clearCountdownTimer() {
    if (!this.countdownTimer) {
      return
    }

    window.clearInterval(
      this.countdownTimer
    )

    this.countdownTimer = null
  }

  clearRoleplayTimer() {
    if (!this.roleplayTimer) {
      return
    }

    window.clearInterval(
      this.roleplayTimer
    )

    this.roleplayTimer = null
  }

  stopMediaStream() {
    if (!this.mediaStream) {
      return
    }

    this.mediaStream
      .getTracks()
      .forEach((track) => {
        track.stop()
      })

    this.mediaStream = null

    if (this.hasPreviewTarget) {
      this.previewTarget.srcObject = null
    }
  }

  supportedVideoMimeType() {
    const candidates = [
      "video/webm;codecs=vp9,opus",
      "video/webm;codecs=vp8,opus",
      "video/webm"
    ]

    return candidates.find((mimeType) => {
      return MediaRecorder.isTypeSupported(
        mimeType
      )
    })
  }

  supportedAudioMimeType() {
    const candidates = [
      "audio/webm;codecs=opus",
      "audio/webm"
    ]

    return candidates.find((mimeType) => {
      return MediaRecorder.isTypeSupported(
        mimeType
      )
    })
  }

  async transcribe(audioBlob) {
    const formData = new FormData()

    formData.append(
      "audio",
      audioBlob,
      "ai_roleplay_turn.webm"
    )

    const response =
      await fetch(
        this.transcribeUrlValue,
        {
          method: "POST",
          headers: this.csrfHeaders(),
          body: formData
        }
      )

    const body =
      await this.parseJson(response)

    if (!response.ok) {
      throw new Error(
        body.error ||
        "音声の文字起こしに失敗しました"
      )
    }

    if (!body.transcription) {
      throw new Error(
        "文字起こし結果が空です"
      )
    }

    return body.transcription
  }

  async createAiResponse(
    clerkMessage
  ) {
    const formData = new FormData()

    formData.append(
      "clerk_message",
      clerkMessage
    )

    formData.append(
      "conversation_history",
      JSON.stringify(
        this.conversationHistory
      )
    )

    const response =
      await fetch(
        this.respondUrlValue,
        {
          method: "POST",
          headers: this.csrfHeaders(),
          body: formData
        }
      )

    const body =
      await this.parseJson(response)

    if (!response.ok) {
      throw new Error(
        body.error ||
        "AI顧客の返答生成に失敗しました"
      )
    }

    if (!body.reply) {
      throw new Error(
        "AI顧客の返答が空です"
      )
    }

    return body
  }

  async synthesize(text) {
    const formData = new FormData()

    formData.append(
      "text",
      text
    )

    const response =
      await fetch(
        this.synthesizeUrlValue,
        {
          method: "POST",
          headers: this.csrfHeaders(),
          body: formData
        }
      )

    if (!response.ok) {
      let message =
        "AI顧客の音声生成に失敗しました"

      try {
        const body =
          await response.json()

        if (body.error) {
          message = body.error
        }
      } catch (_error) {
        /*
         * JSONではないエラーレスポンスの場合は
         * デフォルトメッセージを使用する。
         */
      }

      throw new Error(message)
    }

    return response.blob()
  }

  async playAudio(audioBlob) {
    const handledByMixer =
      await this.playAudioThroughMixer(
        audioBlob
      )

    if (handledByMixer) {
      return
    }

    const audioUrl =
      URL.createObjectURL(audioBlob)

    const audio =
      new Audio(audioUrl)

    try {
      await audio.play()

      await new Promise(
        (resolve, reject) => {
          audio.addEventListener(
            "ended",
            resolve,
            { once: true }
          )

          audio.addEventListener(
            "error",
            () => {
              reject(
                new Error(
                  "AI顧客の音声再生に失敗しました"
                )
              )
            },
            { once: true }
          )
        }
      )
    } finally {
      URL.revokeObjectURL(
        audioUrl
      )
    }
  }

  async playAudioThroughMixer(
    audioBlob
  ) {
    return new Promise(
      (resolve, reject) => {
        let handled = false

        const event =
          new CustomEvent(
            "ai-roleplay:play-audio",
            {
              detail: {
                audioBlob: audioBlob,

                markHandled: () => {
                  handled = true
                },

                resolve: () => {
                  resolve(true)
                },

                reject: (error) => {
                  reject(error)
                }
              }
            }
          )

        window.dispatchEvent(event)

        if (!handled) {
          resolve(false)
        }
      }
    )
  }

  async parseJson(response) {
    try {
      return await response.json()
    } catch (_error) {
      throw new Error(
        "サーバーから不正なレスポンスが返されました"
      )
    }
  }

  csrfHeaders() {
    const token =
      document
        .querySelector(
          'meta[name="csrf-token"]'
        )
        ?.getAttribute("content")

    if (!token) {
      return {}
    }

    return {
      "X-CSRF-Token": token
    }
  }

  setStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent =
        message
    }
  }
}
