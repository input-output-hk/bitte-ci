require "socket"
require "./uuid"
require "./loki"
require "file_utils"
require "./artificer"
require "./libgit2"

module BitteCI
  class Commander
    class Config
      include SimpleConfig::Configuration

      def self.help
        "Executor for steps within Nomad"
      end

      def self.command
        "command"
      end

      @[Option(help: "URL without path used to push logs to Loki")]
      property loki_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(help: "command to run")]
      property command : String

      @[Option(help: "args to pass to the command")]
      property args : Array(String) = Array(String).new

      @[Option(help: "strings to obfuscate in the logs")]
      property obfuscate : Array(String) = Array(String).new

      @[Option(help: %(JSON object or space separated key=value pairs of labels to send to loki e.g. {"foo":"bar"} or foo=bar))]
      property labels : Hash(String, String) = {} of String => String

      @[Option(help: "Seconds to wait until sending SIGTERM to the process")]
      property term_timeout : UInt64 = 60u64 * 30

      @[Option(help: "Seconds to wait until sending SIGKILL to the process")]
      property kill_timeout : UInt64 = 60u64 * 35

      @[Option(help: "Tasks to wait for")]
      property after : Array(String) = [] of String

      @[Option(help: "Name of this task (must be unique within the task group)")]
      property name : String

      @[Option(help: "URL to reach the bitte-ci server for output uploads")]
      property public_url : URI

      @[Option(help: "outputs to upload")]
      property outputs : Array(String) = [] of String

      @[Option(help: "git checkout SHA")]
      property sha : String

      @[Option(secret: true, help: "HMAC secret used for verifying output uploads")]
      property artifact_secret : String

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
      property nomad_job_id : String

      @[Option(help: "Job's name")]
      property nomad_job_name : String

      @[Option(help: "ID of the Job's parent if it has one")]
      property nomad_job_parent_id : UUID?

      @[Option(help: "Namespace in which the allocation is running")]
      property nomad_namespace : String

      @[Option(help: "Region in which the allocation is running")]
      property nomad_region : String

      @[Option(help: "ID for identification in Loki")]
      property bitte_ci_id : UUID

      def to_labels : Hash(String, String)
        {
          "bitte_ci_step"       => name,
          "bitte_ci_id"         => bitte_ci_id.to_s,
          "nomad_alloc_id"      => nomad_alloc_id.to_s,
          "nomad_alloc_index"   => nomad_alloc_index.to_s,
          "nomad_alloc_name"    => nomad_alloc_name,
          "nomad_dc"            => nomad_dc,
          "nomad_group_name"    => nomad_group_name,
          "nomad_job_id"        => nomad_job_id,
          "nomad_job_name"      => nomad_job_name,
          "nomad_job_parent_id" => nomad_job_parent_id.to_s,
          "nomad_namespace"     => nomad_namespace,
          "nomad_region"        => nomad_region,
        }.merge(labels)
      end

      def run(log)
        log.info { "Run Commander" }
        Commander.new(self).run
      end
    end

    REPO_ALLOC = "/alloc/repo"
    REPO_LOCAL = "/local/repo"

    def initialize(@config : Config)
      @loki = Loki.new(@config.loki_base_url, @config.to_labels, @config.obfuscate)
      @timeout = Channel(Signal).new
      @exited = Channel(Process::Status).new
      @returned = Channel(Process::Status).new
    end

    def run
      status = @loki.run do
        copy_repo
        pre_start

        @loki.log "#{@config.command} #{@config.args.join(" ")}"
        process = start_process

        start_forwarder(process)
        start_wait(process)
        start_timeout(@config.term_timeout, Signal::TERM)
        start_timeout(@config.kill_timeout, Signal::KILL)

        @returned.receive
      end

      FileUtils.mkdir_p(status_dir)
      File.write(status_dir / @config.name, status.exit_status.to_s)

      post_start if status.normal_exit? && status.success?

      exit status.exit_status
    end

    def status_dir
      Path.new("/alloc/.bitte-ci")
    end

    def start_process
      chdir = File.directory?(REPO_ALLOC) ? REPO_ALLOC : nil
      @loki.sh(@config.command, @config.args, chdir)
    end

    def copy_repo
      return unless File.directory?(REPO_ALLOC)
      Git.init
      repo = Git.clone(REPO_ALLOC, REPO_LOCAL)
      repo.reset(@config.sha)
      repo.fetch_submodules
    end

    def pre_start
      @config.after.each do |task_name|
        @loki.log "Waiting for completion of step: #{task_name}"
        file = File.join("/alloc/.bitte-ci/", task_name)
        until File.file?(file)
          sleep 1
        end

        dependency_status = Process::Status.new(File.read(status_dir/task_name).to_i)

        unless dependency_status.success?
          raise "Dependency #{task_name} failed with #{dependency_status.exit_status}"
        end
      end
    end

    def post_start
      Artificer.run(@config)
    end

    def start_forwarder(process)
      spawn do
        loop do
          case res = Channel.receive_first(@exited, @timeout)
          in Process::Status
            @returned.send res
            break
          in Signal
            process.signal(res)
          end
        end
      end
    end

    def start_wait(process)
      spawn do
        @exited.send(process.wait)
      end
    end

    def start_timeout(delay, signal)
      spawn do
        sleep delay
        @loki.log "timeout #{delay}s reached, sending SIG#{signal} to process"
        @timeout.send signal
      end
    end
  end
end
