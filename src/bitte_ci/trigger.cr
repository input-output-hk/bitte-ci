require "json"
require "kemal"
require "openssl/hmac"

module BitteCI
  module Trigger
    # Handles the incoming requests from GitHub and invokes the runner for
    # things we care about.
    def self.handle(config, env)
      headers = env.request.headers
      body_io = env.request.body
      event = headers["X-GitHub-Event"]

      case event
      when "star", "watch", "status"
        Log.debug { "unhandled event: #{event}" }
      when "pull_request"
        body = verify_hmac(config.github_hook_secret, headers, body_io) if body_io
        if body
          Runner.run(body, config.for_runner)
        else
          Log.error { "HMAC Signature doesn't match. Verify the github hook and secret configured in bitte-ci match!" }
        end
      else
        Log.info { "unknown event: #{event}" }
      end
    end

    # We verify that the hook body is actually coming from us.
    def self.verify_hmac(secret, headers, body_io : IO)
      body = body_io.gets_to_end
      signature = headers["X-Hub-Signature-256"][7..-1]
      digest = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, body)
      body if digest == signature
    end
  end
end
