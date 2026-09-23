import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "status",
    "startTurnButton",
    "stopTurnButton",
    "transcription",
    "aiReply",
    "customerState"
  ]

  static values = {
    transcribeUrl: String,
    respondUrl: String,
    synthesizeUrl: String
  }

  connect() {
    this.microphoneStream = null
    this.turnRecorder = null
    this.turnChunks = []

    this.setStatus("AIロープレ準備完了")
  }

  disconnect() {
    this.stopMicrophone()
  }

  async startTurn() {
    try {
      this.startTurnButtonTarget.disabled = true
      this.stopTurnButtonTarget.disabled = true

      this.setStatus("マイクを準備しています...")

      await this.ensureMicrophone()

      this.turnChunks = []

      const mimeType = this.supportedAudioMimeType()

      const options = mimeType
        ? { mimeType: mimeType }
        : undefined

      this.turnRecorder = new MediaRecorder(
        this.microphoneStream,
        options
      )

      this.turnRecorder.addEventListener(
        "dataavailable",
        (event) => {
          if (event.data.size > 0) {
            this.turnChunks.push(event.data)
          }
        }
      )

      this.turnRecorder.addEventListener(
        "stop",
        () => {
          this.processTurn()
        },
        { once: true }
      )

      this.turnRecorder.start()

      this.setStatus("店員として話してください")
      this.stopTurnButtonTarget.disabled = false
    } catch (error) {
      console.error(error)

      this.setStatus(
        `マイクの開始に失敗しました: ${error.message}`
      )

      this.startTurnButtonTarget.disabled = false
    }
  }

  stopTurn() {
    if (
      !this.turnRecorder ||
      this.turnRecorder.state !== "recording"
    ) {
      return
    }

    this.stopTurnButtonTarget.disabled = true
    this.setStatus("店員の発話を処理しています...")

    this.turnRecorder.stop()
  }

  async processTurn() {
    try {
      const mimeType =
        this.turnRecorder?.mimeType ||
        this.supportedAudioMimeType() ||
        "audio/webm"

      const audioBlob = new Blob(
        this.turnChunks,
        {
          type: mimeType
        }
      )

      if (audioBlob.size === 0) {
        throw new Error("録音データが空です")
      }

      this.setStatus("音声を文字起こししています...")

      const transcription =
        await this.transcribe(audioBlob)

      this.transcriptionTarget.textContent =
        transcription

      this.setStatus("AI顧客が返答を考えています...")

      const aiResponse =
        await this.createAiResponse(transcription)

      this.aiReplyTarget.textContent =
        aiResponse.reply

      this.customerStateTarget.textContent =
        aiResponse.customer_state

      this.setStatus("AI顧客の音声を生成しています...")

      const aiAudio =
        await this.synthesize(aiResponse.reply)

      this.setStatus("AI顧客が話しています...")

      await this.playAudio(aiAudio)

      if (aiResponse.conversation_end) {
        this.setStatus(
          aiResponse.end_reason ||
          "会話が終了しました"
        )

        return
      }

      this.setStatus("次の店員発話を開始できます")
      this.startTurnButtonTarget.disabled = false
    } catch (error) {
      console.error(error)

      this.setStatus(
        `AIロープレ処理に失敗しました: ${error.message}`
      )

      this.startTurnButtonTarget.disabled = false
      this.stopTurnButtonTarget.disabled = true
    }
  }

  async ensureMicrophone() {
    if (
      this.microphoneStream &&
      this.microphoneStream.active
    ) {
      return
    }

    this.microphoneStream =
      await navigator.mediaDevices.getUserMedia({
        audio: true
      })
  }

  stopMicrophone() {
    if (!this.microphoneStream) {
      return
    }

    this.microphoneStream
      .getTracks()
      .forEach((track) => track.stop())

    this.microphoneStream = null
  }

  supportedAudioMimeType() {
    const candidates = [
      "audio/webm;codecs=opus",
      "audio/webm"
    ]

    return candidates.find((mimeType) => {
      return MediaRecorder.isTypeSupported(mimeType)
    })
  }

  async transcribe(audioBlob) {
    const formData = new FormData()

    formData.append(
      "audio",
      audioBlob,
      "ai_roleplay_turn.webm"
    )

    const response = await fetch(
      this.transcribeUrlValue,
      {
        method: "POST",
        headers: this.csrfHeaders(),
        body: formData
      }
    )

    const body = await this.parseJson(response)

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

  async createAiResponse(clerkMessage) {
    const formData = new FormData()

    formData.append(
      "clerk_message",
      clerkMessage
    )

    const response = await fetch(
      this.respondUrlValue,
      {
        method: "POST",
        headers: this.csrfHeaders(),
        body: formData
      }
    )

    const body = await this.parseJson(response)

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

    const response = await fetch(
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
        const body = await response.json()

        if (body.error) {
          message = body.error
        }
      } catch (_error) {
        // JSONではないエラーレスポンスの場合は
        // デフォルトメッセージを使用する
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

    /*
     * 通常のAIロープレ単体利用時。
     *
     * video-background側で録画していない場合は、
     * 従来どおりAudio要素で再生する。
     */
    const audioUrl =
      URL.createObjectURL(audioBlob)

    const audio = new Audio(audioUrl)

    try {
      await audio.play()

      await new Promise((resolve, reject) => {
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
      })
    } finally {
      URL.revokeObjectURL(audioUrl)
    }
  }

  async playAudioThroughMixer(audioBlob) {
    return new Promise((resolve, reject) => {
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

      /*
       * video-background側で録画用Mixerが
       * 起動していなければイベントは処理されない。
       * その場合は通常のAudio再生へフォールバックする。
       */
      if (!handled) {
        resolve(false)
      }
    })
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
        .querySelector('meta[name="csrf-token"]')
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
      this.statusTarget.textContent = message
    }
  }
}
