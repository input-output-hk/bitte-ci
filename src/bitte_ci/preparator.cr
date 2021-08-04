require "log"
require "socket"
require "file_utils"
require "digest"

require "./uuid"
require "./libgit2"
require "./loki"
require "./simple_config"

module BitteCI
  class Preparator
    class Config
      include SimpleConfig::Configuration

      @[Option(help: "URL to clone the repo from")]
      property clone_url : URI

      @[Option(help: "git checkout SHA")]
      property sha : String
    end

    def self.run(config)
      new(config).run
    end

    def initialize(@config : Config)
    end

    def run
      Log.info &.emit("Starting Preparator", config: @config.inspect)

      Git.init
      repo = Git.clone(@config.clone_url.to_s, "/alloc/repo")
      if repo
        repo.reset(@config.sha)
      else
        raise "Git clone failed"
      end
    end
  end
end
