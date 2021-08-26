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

      def self.help
        "Prepare the repository in /alloc"
      end

      def self.command
        "prepare"
      end

      @[Option(help: "URL to clone the repo from")]
      property clone_url : URI

      @[Option(help: "git checkout SHA")]
      property sha : String

      @[Option(help: "number of the PR")]
      property pr_number : UInt64

      def run(log)
        Preparator.new(log, self).run
      end
    end

    property log : Log
    property config : Config

    def initialize(@log : Log, @config : Config); end

    def run
      log.info {
        "Using commit #{@config.sha} from repo #{@config.clone_url}"
      }

      Git.init
      repo = Git.clone(@config.clone_url.to_s, "/alloc/repo")
      if repo
        remote = repo.remote_lookup("origin")
        Git.remote_fetch(remote, ["refs/pull/#{@config.pr_number}/head"])
        repo.reset(@config.sha)
        repo.fetch_submodules
      else
        raise "Git clone failed"
      end
    end
  end
end
