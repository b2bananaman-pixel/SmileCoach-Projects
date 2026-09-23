require "base64"
require "googleauth"
require "json"
require "net/http"
require "uri"

class GoogleTextToSpeechService
  API_URL = "https://texttospeech.googleapis.com/v1/text:synthesize"
  SCOPE = "https://www.googleapis.com/auth/cloud-platform"
  LANGUAGE_CODE = "ja-JP"
  VOICE_NAME = "ja-JP-Chirp3-HD-Achernar"

  def initialize(text:)
    @text = text
  end

  def call
    raise ArgumentError, "text is required" if @text.blank?

    response = send_request

    unless response.is_a?(Net::HTTPSuccess)
      raise "Google Text-to-Speech API error: #{response.code} #{response.body}"
    end

    body = JSON.parse(response.body)
    audio_content = body["audioContent"]

    raise "Google Text-to-Speech API returned no audio content" if audio_content.blank?

    Base64.decode64(audio_content)
  end

  private

  def send_request
    uri = URI(API_URL)
    credentials = google_credentials
    token = credentials.fetch_access_token!

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token.fetch("access_token")}"
    request["Content-Type"] = "application/json; charset=utf-8"

    if credentials.quota_project_id.present?
      request["x-goog-user-project"] = credentials.quota_project_id
    end

    request.body = request_body.to_json

    Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: true
    ) do |http|
      http.request(request)
    end
  end

  def google_credentials
    Google::Auth.get_application_default([ SCOPE ])
  end

  def request_body
    {
      input: {
        text: @text
      },
      voice: {
        languageCode: LANGUAGE_CODE,
        name: VOICE_NAME
      },
      audioConfig: {
        audioEncoding: "MP3"
      }
    }
  end
end
