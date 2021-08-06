require "digest"
require "file_utils"
require "./simple_config"
require "./magic"

module BitteCI
  class Artificer
    MAX_FILESIZE = 100 * 1e6 # MB

    def self.handle(config, env)
      Clear::SQL.init(config.postgres_url.to_s)
      Clear::Log.level = :debug

      pp! env.request

      mime = env.request.headers["Content-Type"]
      nomad_alloc_id = env.request.query_params["nomad_alloc_id"]
      path = env.request.query_params["path"]
      hash = env.request.query_params["sha256"]

      body = env.request.body
      unless body
        raise "Request body with the file required"
      end

      content_length = env.request.headers["Content-Length"]?
      if content_length && content_length.to_u64 > MAX_FILESIZE
        raise "File larger than #{MAX_FILESIZE.humanize}"
      end

      unless hash =~ /^[0-9a-f]{64}$/
        raise "sha256 is not valid"
      end

      # this should spread the files out across a few thousand directories
      dest = File.join("output", hash[0..5], hash)
      FileUtils.mkdir_p(File.dirname(dest))
      File.open(dest, "w+") do |file|
        IO.copy(body, file)
      end

      if File.size(dest) > MAX_FILESIZE
        File.delete(dest)
        raise "File larger than #{MAX_FILESIZE.humanize}"
      end

      # generating the digest from the file saves a lot of memory as we can
      # stream the request body to disk first.
      # Only drawback is when the hash doesn't match we have to clean up...
      final = Digest::SHA256.hexdigest &.file(dest)

      if hash != final
        File.delete(dest)
        raise "body doesn't match sha256, got: #{final} and expected: #{hash}"
      end

      output = Output.create(
        path: path,
        sha256: hash,
        size: File.size(dest),
        created_at: Time.utc,
        alloc_id: nomad_alloc_id,
        mime: mime,
      )

      output.inspect
    end

    def self.run(config)
      Log.info { "Starting artificer for Nomad Alloc #{config.nomad_alloc_id} for outputs: #{config.outputs}" }
      Dir.glob(config.outputs, match_hidden: true, follow_symlinks: true) do |match|
        Log.info { "Storing #{match}" }
        upload(config, match)
      end
    end

    def self.upload(config, path)
      uri = config.public_url.dup
      uri.path = "/api/v1/output"
      uri.query = URI::Params.build { |form|
        form.add "nomad_alloc_id", config.nomad_alloc_id.to_s
        form.add "path", path
        form.add "sha256", Digest::SHA256.hexdigest &.file(path)
      }

      res =
        File.open path do |io|
          HTTP::Client.put(
            uri,
            body: io,
            headers: HTTP::Headers{"Content-Type" => detect_mime(path)}
          )
        end

      case res.status
      when HTTP::Status::CREATED
        res
      else
        Log.error &.emit("response", response: res.inspect)
        Log.error {
          "HTTP Error while trying to PUT output to #{uri} : #{res.status.to_i} #{res.status_message}"
        }
      end
    end

    def self.detect_mime(path) : String
      Log.info { "Detecting mime-type of #{path}" }
      mime = Magic::Magic.new(Magic::MagicFlags::MIME).file(path).to_s
      Log.info { "Mime is #{mime}" }
      mime.empty? ? "application/octet-stream" : mime
    end
  end
end
