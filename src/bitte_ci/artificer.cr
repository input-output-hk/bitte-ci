require "./simple_config"

module BitteCI
  class Artificer
    struct Config
      include SimpleConfig::Configuration

      @[Option(secret: true, help: "PostgreSQL URL e.g. postgres://postgres@127.0.0.1:54321/bitte_ci")]
      property postgres_url : URI

      @[Option(help: "Nomad Alloc UUID")]
      property nomad_alloc_id : UUID

      @[Option(help: "Globs of files to store as build output")]
      property outputs : Array(String)
    end

    def self.run(config)
      new(config).run
    end

    getter config : Config

    def initialize(@config : Config)
      Clear::SQL.init(config.postgres_url.to_s)
    end

    def run
      Log.info { "Starting artificer for Nomad Alloc #{config.nomad_alloc_id} for outputs: #{config.outputs}" }
      Dir.glob(config.outputs, match_hidden: true, follow_symlinks: true) do |match|
        Log.info { "Storing #{match}" }
        store(match)
      end
    end

    def store(path)
      info = File.info(File.expand_path(path))
      return unless info.file?

      data = Bytes.new(info.size)
      File.open(path) { |io| io.read_fully(data) }

      output = Output.create(
        path: path,
        data: data,
        size: data.size,
        created_at: info.modification_time,
        alloc_id: config.nomad_alloc_id,
        mime: detect_mime(path),
      )

      pp! output
    end

    def detect_mime(path) : String
      output = IO::Memory.new
      Log.info { "Detecting mime-type of #{path}" }
      Process.run("file", args: ["--mime", path], output: output, error: STDERR)
      mime = output.to_s.strip
      mime.empty? ? "application/octet-stream" : mime
    end
  end
end
