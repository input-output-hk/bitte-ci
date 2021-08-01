require "socket"
require "uuid"
require "./simple_config"

module BitteCI
  class Preparator
    class Config
      include SimpleConfig::Configuration

      @[Option(help: "URL without path used to push logs to Loki")]
      property loki_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(help: %(JSON object or space separated key=value pairs of labels to send to loki e.g. {"foo":"bar"} or foo=bar))]
      property labels : Hash(String, String) = {} of String => String

      @[Option(help: "Seconds to wait until sending SIGTERM to the process")]
      property term_timeout : UInt64 = 60u64 * 30

      @[Option(help: "Seconds to wait until sending SIGKILL to the process")]
      property kill_timeout : UInt64 = 60u64 * 35

      @[Option(help: "URL to clone the repo from")]
      property clone_url : URI

      @[Option(help: "git checkout SHA")]
      property sha : String

      # Everything below here is usually set by Nomad through environment variables

      @[Option(help: "Allocation ID of the task")]
      property nomad_alloc_id : UUID

      @[Option(help: "Allocation index; useful to distinguish instances of task groups.")]
      property nomad_alloc_index : UInt64

      @[Option(help: "Allocation name of the task")]
      property nomad_alloc_name : String

      @[Option(help: "Datacenter in which the allocation is running")]
      property nomad_dc : String

      @[Option(help: "Group's name")]
      property nomad_group_name : String

      @[Option(help: "Job's ID")]
      property nomad_job_id : UUID

      @[Option(help: "Job's name")]
      property nomad_job_name : String

      @[Option(help: "ID of the Job's parent if it has one")]
      property nomad_job_parent_id : UUID?

      @[Option(help: "Namespace in which the allocation is running")]
      property nomad_namespace : String

      @[Option(help: "Region in which the allocation is running")]
      property nomad_region : String

      def to_labels : Hash(String, String)
        {
          "nomad_alloc_id"      => nomad_alloc_id.to_s,
          "nomad_alloc_index"   => nomad_alloc_index.to_s,
          "nomad_alloc_name"    => nomad_alloc_name,
          "nomad_dc"            => nomad_dc,
          "nomad_group_name"    => nomad_group_name,
          "nomad_job_id"        => nomad_job_id.to_s,
          "nomad_job_name"      => nomad_job_name,
          "nomad_job_parent_id" => nomad_job_parent_id.to_s,
          "nomad_namespace"     => nomad_namespace,
          "nomad_region"        => nomad_region,
        }.merge(labels)
      end
    end

    def self.run(config)
      new(config).run
    end

    def initialize(@config : Config)
      @loki = Loki.new(@config.loki_base_url, labels: @config.to_labels)
    end

    def run
      Log.info { "Starting Preparator" }

      path = "/alloc/repo"
      FileUtils.mkdir_p path

      @loki.start do
        repo = Git.clone(@config.clone_url.to_s, path)
        Git.reset(repo, @config.sha)

        # sh("git", "-C", repo, "init")
        # sh("git", "-C", repo, "remote", "add", "origin", @config.clone_url.to_s)
        # sh("git", "-C", repo, "fetch", "origin", @config.sha)
        # sh("git", "-C", repo, "reset", "--hard", "FETCH_HEAD")
      end
    end

    def sh(cmd, *args)
      result = @loki.sh(cmd, args: args)
      exit result.exit_status unless result.success?
    end
  end
end
