require "json"
require "kemal"
require "openssl/hmac"

module BitteCI
  module Trigger
    def self.handle(config, env)
      headers = env.request.headers
      body_io = env.request.body
      event = headers["X-GitHub-Event"]

      case event
      when "star", "watch"
        Log.debug { "unhandled event: #{event}" }
      when "pull_request"
        body = verify(config, headers, body_io) if body_io
        if body
          Runner.run(body, config)
        else
          Log.error { "HMAC Signature doesn't match. Verify the github hook and secret configured in bitte-ci match!" }
        end
      else
        Log.debug { "unknown event: #{event}" }
      end
    end

    def self.verify(config, headers, body_io : IO)
      body = body_io.gets_to_end
      signature = headers["X-Hub-Signature-256"][7..-1]
      digest = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, config.secret, body)
      body if digest == signature
    end
  end
end
