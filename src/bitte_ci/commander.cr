require "socket"

module BitteCI
  class Commander
    class Config
      include SimpleConfig::Configuration

      @[Option(help: "URL without path used to push logs to Loki")]
      property loki_base_url = URI.parse("http://127.0.0.1:4646")

      @[Option(help: "command to run")]
      property command : String

      @[Option(help: "args to pass to the command")]
      property args : Array(String) = Array(String).new

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
      property bitte_ci_base_url : URI

      @[Option(help: "outputs to upload")]
      property outputs : Array(String) = [] of String

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
      @loki = Loki.new(@config.loki_base_url, @config.to_labels)
      @timeout = Channel(Signal).new
      @exit_status = 1
    end

    def run
      Log.info { "Starting Commander" }

      pre_start

      @loki.start do
        start_timeout

        @loki.sh(@config.command, @config.args) do |process|
          spawn do
            while signal = @timeout.receive
              Log.error { "timeout reached, sending SIG#{signal} to process" }
              process.signal(signal)
            end
          end

          @exit_status = process.wait.exit_status

          FileUtils.mkdir_p("/alloc/.bitte-ci")
          File.touch(File.join("/alloc/.bitte-ci", @config.name))
        end
      end

      post_start if @exit_status == 0

      exit @exit_status
    end

    def pre_start
      @config.after.each do |task_name|
        Log.info { "Waiting for completion of #{task_name}" }
        file = File.join("/alloc/.bitte-ci/", task_name)
        until File.file?(file)
          sleep 1
        end
      end
    end

    def post_start
      Artificer.run(@config)
    end

    def start_timeout
      spawn do
        sleep @config.term_timeout
        @timeout.send Signal::TERM
      end

      spawn do
        sleep @config.kill_timeout
        @timeout.send Signal::KILL
        @timeout.close
      end
    end
  end
end
