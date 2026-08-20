require "net/http"
require "uri"
require "json"
require "securerandom"

class GroqTranscriptionService
  API_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
  MODEL = "whisper-large-v3-turbo"

  def initialize(audio_file, http_client: Net::HTTP)
    @audio_file = audio_file
    @http_client = http_client
  end

  def call
    uri = URI(API_URL)

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{ENV.fetch("GROQ_API_KEY")}"

    boundary = "----RubyMultipartBoundary#{SecureRandom.hex}"
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"

    file_data = @audio_file.download

    body = []
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"model\"\r\n\r\n"
    body << "#{MODEL}\r\n"
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"language\"\r\n\r\n"
    body << "ja\r\n"
    body << "--#{boundary}\r\n"
    body << "Content-Disposition: form-data; name=\"file\"; filename=\"practice_audio.webm\"\r\n"
    body << "Content-Type: audio/webm\r\n\r\n"
    body << file_data
    body << "\r\n--#{boundary}--\r\n"

    request.body = body.join

    response = @http_client.start(
      uri.hostname,
      uri.port,
      use_ssl: true
    ) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise "Groq API request failed: #{response.code} #{response.body}"
    end

    JSON.parse(response.body)
  end
end
