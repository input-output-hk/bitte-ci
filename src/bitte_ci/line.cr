require "json"
require "./time"
require "./uuid"

module BitteCI
  class Listener
    class Line
      include JSON::Serializable

      @[JSON::Field(key: "Index")]
      property index : UInt64

      @[JSON::Field(key: "Events")]
      property events : Array(Event)
    end

    abstract class Event
      include JSON::Serializable

      use_json_discriminator "Topic", {
        Allocation: Allocation,
        Deployment: Deployment,
        Evaluation: Evaluation,
        Job:        Job,
        Node:       Node,
      }

      @[JSON::Field(key: "Topic")]
      property topic : String

      @[JSON::Field(key: "Namespace")]
      property namespace : String

      @[JSON::Field(key: "FilterKeys")]
      property filter_keys : Array(String)?

      @[JSON::Field(key: "Key")]
      property key : String

      @[JSON::Field(key: "Index")]
      property index : UInt64
    end

    class Allocation < Event
      @[JSON::Field(key: "Payload")]
      property payload : AllocationPayload
    end

    class Deployment < Event
    end

    class Evaluation < Event
      @[JSON::Field(key: "Payload")]
      property payload : EvaluationPayload

      class EvaluationPayload
        include JSON::Serializable

        @[JSON::Field(key: "Evaluation")]
        property evaluation : Evaluation

        class Evaluation
          include JSON::Serializable

          @[JSON::Field(key: "CreateIndex")]
          property create_index : UInt64

          @[JSON::Field(key: "CreateTime", converter: Time::EpochNanosConverter)]
          property create_time : Time

          @[JSON::Field(key: "ID")]
          property id : UUID

          @[JSON::Field(key: "JobID")]
          property job_id : String

          @[JSON::Field(key: "JobModifyIndex")]
          property job_modify_index : UInt64?

          @[JSON::Field(key: "ModifyIndex")]
          property modify_index : UInt64

          @[JSON::Field(key: "ModifyTime")]
          property modify_time : UInt64

          @[JSON::Field(key: "ModifyTime", converter: Time::EpochNanosConverter)]
          property modify_time : Time

          @[JSON::Field(key: "Namespace")]
          property namespace : String

          @[JSON::Field(key: "PreviousEval")]
          property previous_eval : UUID?

          @[JSON::Field(key: "Priority")]
          property priority : UInt64

          @[JSON::Field(key: "QueuedAllocations")]
          property queued_allocations : Hash(String, UInt64)?

          @[JSON::Field(key: "SnapshotIndex")]
          property snapshot_index : UInt64?

          @[JSON::Field(key: "Status")]
          property status : String

          @[JSON::Field(key: "TriggeredBy")]
          property triggered_by : String

          @[JSON::Field(key: "Type")]
          property type : String

          @[JSON::Field(key: "WaitUntil")]
          property wait_until : Time?
        end
      end
    end

    class Job < Event
      @[JSON::Field(key: "Payload")]
      property payload : JobPayload

      class JobPayload
        include JSON::Serializable

        @[JSON::Field(key: "Job")]
        property job : Job

        class Job
          include JSON::Serializable

          @[JSON::Field(key: "Affinities")]
          property affinities : Nil

          @[JSON::Field(key: "AllAtOnce")]
          property all_at_once : Bool

          @[JSON::Field(key: "Constraints")]
          property constraints : Nil

          @[JSON::Field(key: "ConsulNamespace")]
          property consul_namespace : String

          @[JSON::Field(key: "ConsulToken")]
          property consul_token : String

          @[JSON::Field(key: "CreateIndex")]
          property create_index : UInt64

          @[JSON::Field(key: "Datacenters")]
          property datacenters : Array(String)

          @[JSON::Field(key: "DispatchIdempotencyToken")]
          property dispatch_idempotency_token : String

          @[JSON::Field(key: "Dispatched")]
          property dispatched : Bool

          @[JSON::Field(key: "ID")]
          property id : String

          @[JSON::Field(key: "JobModifyIndex")]
          property job_modify_index : UInt64

          @[JSON::Field(key: "Meta")]
          property meta : Hash(String, String)?

          @[JSON::Field(key: "ModifyIndex")]
          property modify_index : UInt64

          @[JSON::Field(key: "Multiregion")]
          property multiregion : Nil

          @[JSON::Field(key: "Name")]
          property name : String

          @[JSON::Field(key: "Namespace")]
          property namespace : String

          @[JSON::Field(key: "NomadTokenID")]
          property nomad_token_id : String

          @[JSON::Field(key: "ParameterizedJob")]
          property parameterized_job : Nil

          @[JSON::Field(key: "ParentID")]
          property parent_id : String

          @[JSON::Field(key: "Payload")]
          property payload : Nil

          @[JSON::Field(key: "Periodic")]
          property periodic : Nil

          @[JSON::Field(key: "Priority")]
          property priority : UInt64

          @[JSON::Field(key: "Region")]
          property region : String

          @[JSON::Field(key: "Spreads")]
          property spreads : Nil

          @[JSON::Field(key: "Stable")]
          property stable : Bool

          @[JSON::Field(key: "Status")]
          property status : String

          @[JSON::Field(key: "StatusDescription")]
          property status_description : String

          @[JSON::Field(key: "Stop")]
          property stop : Bool

          @[JSON::Field(key: "SubmitTime", converter: Time::EpochNanosConverter)]
          property submit_time : Time

          @[JSON::Field(key: "TaskGroups")]
          property task_groups : Array(TaskGroup)

          @[JSON::Field(key: "Type")]
          property job_type : String

          @[JSON::Field(key: "Update")]
          property update : Update

          @[JSON::Field(key: "VaultNamespace")]
          property vault_namespace : String

          @[JSON::Field(key: "VaultToken")]
          property vault_token : String

          @[JSON::Field(key: "Version")]
          property version : UInt64
        end

        class TaskGroup
          include JSON::Serializable

          @[JSON::Field(key: "Affinities")]
          property affinities : Nil

          @[JSON::Field(key: "Constraints")]
          property constraints : Array(Constraint)

          @[JSON::Field(key: "Consul")]
          property consul : Consul

          @[JSON::Field(key: "Count")]
          property count : UInt64

          @[JSON::Field(key: "EphemeralDisk")]
          property ephemeral_disk : EphemeralDisk

          @[JSON::Field(key: "Meta")]
          property meta : Hash(String, String)?

          @[JSON::Field(key: "Migrate")]
          property migrate : Nil

          @[JSON::Field(key: "Name")]
          property name : String

          @[JSON::Field(key: "Networks")]
          property networks : Array(Network)

          @[JSON::Field(key: "ReschedulePolicy")]
          property reschedule_policy : ReschedulePolicy

          @[JSON::Field(key: "RestartPolicy")]
          property restart_policy : RestartPolicy

          @[JSON::Field(key: "Scaling")]
          property scaling : Nil

          @[JSON::Field(key: "Services")]
          property services : Nil

          @[JSON::Field(key: "ShutdownDelay")]
          property shutdown_delay : Nil

          @[JSON::Field(key: "Spreads")]
          property spreads : Nil

          @[JSON::Field(key: "StopAfterClientDisconnect")]
          property stop_after_client_disconnect : UInt64?

          @[JSON::Field(key: "Tasks")]
          property tasks : Array(Task)

          @[JSON::Field(key: "Update")]
          property update : Nil

          @[JSON::Field(key: "Volumes")]
          property volumes : Nil
        end

        class Constraint
          include JSON::Serializable

          @[JSON::Field(key: "LTarget")]
          property l_target : String

          @[JSON::Field(key: "Operand")]
          property operand : String

          @[JSON::Field(key: "RTarget")]
          property r_target : String
        end

        class Consul
          include JSON::Serializable

          @[JSON::Field(key: "Namespace")]
          property namespace : String
        end

        class EphemeralDisk
          include JSON::Serializable

          @[JSON::Field(key: "Migrate")]
          property migrate : Bool

          @[JSON::Field(key: "SizeMB")]
          property size_mb : UInt64

          @[JSON::Field(key: "Sticky")]
          property sticky : Bool
        end

        class Network
          include JSON::Serializable

          @[JSON::Field(key: "CIDR")]
          property cidr : String

          @[JSON::Field(key: "DNS")]
          property dns : Nil

          @[JSON::Field(key: "Device")]
          property device : String

          @[JSON::Field(key: "DynamicPorts")]
          property dynamic_ports : Nil

          @[JSON::Field(key: "IP")]
          property ip : String

          @[JSON::Field(key: "MBits")]
          property m_bits : UInt64

          @[JSON::Field(key: "Mode")]
          property mode : String

          @[JSON::Field(key: "ReservedPorts")]
          property reserved_ports : Nil
        end

        class ReschedulePolicy
          include JSON::Serializable

          @[JSON::Field(key: "Attempts")]
          property attempts : UInt64

          @[JSON::Field(key: "Delay")]
          property delay : UInt64

          @[JSON::Field(key: "DelayFunction")]
          property delay_function : String

          @[JSON::Field(key: "Interval")]
          property interval : UInt64

          @[JSON::Field(key: "MaxDelay")]
          property max_delay : UInt64

          @[JSON::Field(key: "Unlimited")]
          property unlimited : Bool
        end

        class RestartPolicy
          include JSON::Serializable

          @[JSON::Field(key: "Attempts")]
          property attempts : UInt64

          @[JSON::Field(key: "Delay")]
          property delay : UInt64

          @[JSON::Field(key: "Interval")]
          property interval : UInt64

          @[JSON::Field(key: "Mode")]
          property mode : String
        end

        class Task
          include JSON::Serializable

          @[JSON::Field(key: "Affinities")]
          property affinities : Nil

          @[JSON::Field(key: "Artifacts")]
          property artifacts : Nil

          @[JSON::Field(key: "CSIPluginConfig")]
          property csi_plugin_config : Nil

          @[JSON::Field(key: "Config")]
          property config : Config

          @[JSON::Field(key: "Constraints")]
          property constraints : Nil

          @[JSON::Field(key: "DispatchPayload")]
          property dispatch_payload : Nil

          @[JSON::Field(key: "Driver")]
          property driver : String

          @[JSON::Field(key: "Env")]
          property env : Hash(String, String)?

          @[JSON::Field(key: "KillSignal")]
          property kill_signal : String

          @[JSON::Field(key: "KillTimeout")]
          property kill_timeout : UInt64

          @[JSON::Field(key: "Kind")]
          property kind : String

          @[JSON::Field(key: "Leader")]
          property leader : Bool

          @[JSON::Field(key: "Lifecycle")]
          property lifecycle : Lifecycle?

          @[JSON::Field(key: "LogConfig")]
          property log_config : LogConfig

          @[JSON::Field(key: "Meta")]
          property meta : Hash(String, String)?

          @[JSON::Field(key: "Name")]
          property name : String

          @[JSON::Field(key: "Resources")]
          property resources : Resources

          @[JSON::Field(key: "RestartPolicy")]
          property restart_policy : RestartPolicy

          @[JSON::Field(key: "ScalingPolicies")]
          property scaling_policies : Nil

          @[JSON::Field(key: "Services")]
          property services : Nil

          @[JSON::Field(key: "ShutdownDelay")]
          property shutdown_delay : UInt64

          @[JSON::Field(key: "Templates")]
          property templates : Array(Template)

          @[JSON::Field(key: "User")]
          property user : String

          @[JSON::Field(key: "Vault")]
          property vault : Nil

          @[JSON::Field(key: "VolumeMounts")]
          property volume_mounts : Array(VolumeMount)?
        end

        class VolumeMount
          include JSON::Serializable

          property fixme : String
        end

        class Config
          include JSON::Serializable

          property command : String

          property args : Array(String)

          property flake_deps : Array(String)
        end

        class Lifecycle
          include JSON::Serializable

          @[JSON::Field(key: "Hook")]
          property hook : String

          @[JSON::Field(key: "Sidecar")]
          property sidecar : Bool
        end

        class LogConfig
          include JSON::Serializable

          @[JSON::Field(key: "MaxFileSizeMB")]
          property max_file_size_mb : UInt64

          @[JSON::Field(key: "MaxFiles")]
          property max_files : UInt64
        end

        class Resources
          include JSON::Serializable

          @[JSON::Field(key: "CPU")]
          property cpu : UInt64

          @[JSON::Field(key: "Cores")]
          property cores : UInt64

          @[JSON::Field(key: "Devices")]
          property devices : Nil

          @[JSON::Field(key: "DiskMB")]
          property disk_mb : UInt64

          @[JSON::Field(key: "IOPS")]
          property iops : UInt64

          @[JSON::Field(key: "MemoryMB")]
          property memory_mb : UInt64

          @[JSON::Field(key: "MemoryMaxMB")]
          property memory_max_mb : UInt64

          @[JSON::Field(key: "Networks")]
          property networks : Nil
        end

        class Template
          include JSON::Serializable

          @[JSON::Field(key: "ChangeMode")]
          property change_mode : String

          @[JSON::Field(key: "ChangeSignal")]
          property change_signal : String

          @[JSON::Field(key: "DestPath")]
          property dest_path : String

          @[JSON::Field(key: "EmbeddedTmpl")]
          property embedded_tmpl : String

          @[JSON::Field(key: "Envvars")]
          property envvars : Bool

          @[JSON::Field(key: "LeftDelim")]
          property left_delim : String

          @[JSON::Field(key: "Perms")]
          property perms : String

          @[JSON::Field(key: "RightDelim")]
          property right_delim : String

          @[JSON::Field(key: "SourcePath")]
          property source_path : String

          @[JSON::Field(key: "Splay")]
          property splay : UInt64

          @[JSON::Field(key: "VaultGrace")]
          property vault_grace : UInt64
        end

        class Update
          include JSON::Serializable

          @[JSON::Field(key: "AutoPromote")]
          property auto_promote : Bool

          @[JSON::Field(key: "AutoRevert")]
          property auto_revert : Bool

          @[JSON::Field(key: "Canary")]
          property canary : UInt64

          @[JSON::Field(key: "HealthCheck")]
          property health_check : String

          @[JSON::Field(key: "HealthyDeadline")]
          property healthy_deadline : UInt64

          @[JSON::Field(key: "MaxParallel")]
          property max_parallel : UInt64

          @[JSON::Field(key: "MinHealthyTime")]
          property min_healthy_time : UInt64

          @[JSON::Field(key: "ProgressDeadline")]
          property progress_deadline : UInt64

          @[JSON::Field(key: "Stagger")]
          property stagger : UInt64
        end
      end
    end

    class Node < Event
      @[JSON::Field(key: "Payload")]
      property payload : NodePayload

      class NodePayload
        include JSON::Serializable

        @[JSON::Field(key: "Node")]
        property node : Node

        class Node
          include JSON::Serializable

          @[JSON::Field(key: "Attributes")]
          property attributes : Hash(String, String)

          @[JSON::Field(key: "CSIControllerPlugins")]
          property csi_controller_plugins : Nil

          @[JSON::Field(key: "CSINodePlugins")]
          property csi_node_plugins : Nil

          @[JSON::Field(key: "ComputedClass")]
          property computed_class : String

          @[JSON::Field(key: "CreateIndex")]
          property create_index : UInt64

          @[JSON::Field(key: "Datacenter")]
          property datacenter : String

          @[JSON::Field(key: "Drain")]
          property drain : Bool

          @[JSON::Field(key: "DrainStrategy")]
          property drain_strategy : Nil

          @[JSON::Field(key: "Drivers")]
          property drivers : Hash(String, Driver)

          @[JSON::Field(key: "Events")]
          property events : Array(EventElement)

          @[JSON::Field(key: "HTTPAddr")]
          property http_addr : String

          @[JSON::Field(key: "HostVolumes")]
          property host_volumes : Nil

          @[JSON::Field(key: "ID")]
          property id : String

          @[JSON::Field(key: "LastDrain")]
          property last_drain : Nil

          @[JSON::Field(key: "Links")]
          property links : Nil

          @[JSON::Field(key: "Meta")]
          property meta : Hash(String, String)?

          @[JSON::Field(key: "ModifyIndex")]
          property modify_index : UInt64

          @[JSON::Field(key: "Name")]
          property name : String

          @[JSON::Field(key: "NodeClass")]
          property node_class : String

          @[JSON::Field(key: "NodeResources")]
          property node_resources : NodeResources

          @[JSON::Field(key: "Reserved")]
          property reserved : Res

          @[JSON::Field(key: "ReservedResources")]
          property reserved_resources : ReservedResources

          @[JSON::Field(key: "Resources")]
          property resources : Res

          @[JSON::Field(key: "SchedulingEligibility")]
          property scheduling_eligibility : String

          @[JSON::Field(key: "SecretID")]
          property secret_id : String

          @[JSON::Field(key: "Status")]
          property status : String

          @[JSON::Field(key: "StatusDescription")]
          property status_description : String

          @[JSON::Field(key: "StatusUpdatedAt", converter: Time::EpochNanosConverter)]
          property status_updated_at : Time

          @[JSON::Field(key: "TLSEnabled")]
          property tls_enabled : Bool
        end

        class Driver
          include JSON::Serializable

          @[JSON::Field(key: "Attributes")]
          property attributes : Hash(String, String)

          @[JSON::Field(key: "Detected")]
          property detected : Bool

          @[JSON::Field(key: "HealthDescription")]
          property health_description : String

          @[JSON::Field(key: "Healthy")]
          property healthy : Bool

          @[JSON::Field(key: "UpdateTime")]
          property update_time : Time
        end

        class EventElement
          include JSON::Serializable

          @[JSON::Field(key: "CreateIndex")]
          property create_index : UInt64

          @[JSON::Field(key: "Details")]
          property details : Nil

          @[JSON::Field(key: "Message")]
          property message : String

          @[JSON::Field(key: "Subsystem")]
          property subsystem : String

          @[JSON::Field(key: "Timestamp")]
          property timestamp : Time
        end

        class NodeResources
          include JSON::Serializable

          @[JSON::Field(key: "Cpu")]
          property cpu : NodeResourcesCpu

          @[JSON::Field(key: "Devices")]
          property devices : Nil

          @[JSON::Field(key: "Disk")]
          property disk : Disk

          @[JSON::Field(key: "Memory")]
          property memory : Memory

          @[JSON::Field(key: "Networks")]
          property networks : Array(Network)

          @[JSON::Field(key: "NodeNetworks")]
          property node_networks : Array(NodeNetwork)
        end

        class NodeResourcesCpu
          include JSON::Serializable

          @[JSON::Field(key: "CpuShares")]
          property cpu_shares : UInt64

          @[JSON::Field(key: "ReservableCpuCores")]
          property reservable_cpu_cores : Nil

          @[JSON::Field(key: "TotalCpuCores")]
          property total_cpu_cores : UInt64
        end

        class Disk
          include JSON::Serializable

          @[JSON::Field(key: "DiskMB")]
          property disk_mb : UInt64
        end

        class Memory
          include JSON::Serializable

          @[JSON::Field(key: "MemoryMB")]
          property memory_mb : UInt64
        end

        class Network
          include JSON::Serializable

          @[JSON::Field(key: "CIDR")]
          property cidr : String

          @[JSON::Field(key: "DNS")]
          property dns : Nil

          @[JSON::Field(key: "Device")]
          property device : String

          @[JSON::Field(key: "DynamicPorts")]
          property dynamic_ports : Nil

          @[JSON::Field(key: "IP")]
          property ip : String

          @[JSON::Field(key: "MBits")]
          property m_bits : UInt64

          @[JSON::Field(key: "Mode")]
          property mode : String

          @[JSON::Field(key: "ReservedPorts")]
          property reserved_ports : Nil
        end

        class NodeNetwork
          include JSON::Serializable

          @[JSON::Field(key: "Addresses")]
          property addresses : Array(Address)?

          @[JSON::Field(key: "Device")]
          property device : String

          @[JSON::Field(key: "MacAddress")]
          property mac_address : String

          @[JSON::Field(key: "Mode")]
          property mode : String

          @[JSON::Field(key: "Speed")]
          property speed : UInt64
        end

        class Address
          include JSON::Serializable

          @[JSON::Field(key: "Address")]
          property address : String

          @[JSON::Field(key: "Alias")]
          property address_alias : String

          @[JSON::Field(key: "Family")]
          property family : String

          @[JSON::Field(key: "Gateway")]
          property gateway : String

          @[JSON::Field(key: "ReservedPorts")]
          property reserved_ports : String
        end

        class Res
          include JSON::Serializable

          @[JSON::Field(key: "CPU")]
          property cpu : UInt64

          @[JSON::Field(key: "Cores")]
          property cores : UInt64

          @[JSON::Field(key: "Devices")]
          property devices : Nil

          @[JSON::Field(key: "DiskMB")]
          property disk_mb : UInt64

          @[JSON::Field(key: "IOPS")]
          property iops : UInt64

          @[JSON::Field(key: "MemoryMB")]
          property memory_mb : UInt64

          @[JSON::Field(key: "MemoryMaxMB")]
          property memory_max_mb : UInt64

          @[JSON::Field(key: "Networks")]
          property networks : Array(Network)?
        end

        class ReservedResources
          include JSON::Serializable

          @[JSON::Field(key: "Cpu")]
          property cpu : ReservedResourcesCpu

          @[JSON::Field(key: "Disk")]
          property disk : Disk

          @[JSON::Field(key: "Memory")]
          property memory : Memory

          @[JSON::Field(key: "Networks")]
          property networks : Networks
        end

        class ReservedResourcesCpu
          include JSON::Serializable

          @[JSON::Field(key: "CpuShares")]
          property cpu_shares : UInt64

          @[JSON::Field(key: "ReservedCpuCores")]
          property reserved_cpu_cores : Nil
        end

        class Networks
          include JSON::Serializable

          @[JSON::Field(key: "ReservedHostPorts")]
          property reserved_host_ports : String
        end
      end
    end

    class AllocationPayload
      include JSON::Serializable

      @[JSON::Field(key: "Allocation")]
      property allocation : Allocation

      class Allocation
        include JSON::Serializable

        @[JSON::Field(key: "AllocModifyIndex")]
        property alloc_modify_index : UInt64

        @[JSON::Field(key: "AllocatedResources")]
        property allocated_resources : AllocatedResources

        @[JSON::Field(key: "ClientDescription")]
        property client_description : String?

        @[JSON::Field(key: "ClientStatus")]
        property client_status : String

        @[JSON::Field(key: "CreateIndex")]
        property create_index : UInt64

        @[JSON::Field(key: "CreateTime", converter: Time::EpochNanosConverter)]
        property create_time : Time

        @[JSON::Field(key: "DesiredStatus")]
        property desired_status : String

        @[JSON::Field(key: "EvalID")]
        property eval_id : UUID

        @[JSON::Field(key: "ID")]
        property id : UUID

        @[JSON::Field(key: "JobID")]
        property job_id : String

        @[JSON::Field(key: "Metrics")]
        property metrics : Metrics

        @[JSON::Field(key: "ModifyIndex")]
        property modify_index : UInt64

        @[JSON::Field(key: "ModifyTime", converter: Time::EpochNanosConverter)]
        property modify_time : Time

        @[JSON::Field(key: "Name")]
        property name : String

        @[JSON::Field(key: "Namespace")]
        property namespace : String

        @[JSON::Field(key: "NetworkStatus")]
        property network_status : NetworkStatus?

        @[JSON::Field(key: "NodeID")]
        property node_id : UUID

        @[JSON::Field(key: "NodeName")]
        property node_name : String

        @[JSON::Field(key: "PreviousAllocation")]
        property previous_allocation : UUID?

        @[JSON::Field(key: "RescheduleTracker")]
        property reschedule_tracker : RescheduleTracker?

        @[JSON::Field(key: "Resources")]
        property resources : Resources

        @[JSON::Field(key: "SharedResources")]
        property shared_resources : Resources

        @[JSON::Field(key: "TaskGroup")]
        property task_group : String

        @[JSON::Field(key: "TaskResources")]
        property task_resources : Hash(String, Resources)

        @[JSON::Field(key: "TaskStates")]
        property task_states : Hash(String, TaskStates)?

        class TaskStates
          include JSON::Serializable

          @[JSON::Field(key: "Events")]
          property events : Array(Event)

          @[JSON::Field(key: "Failed")]
          property failed : Bool

          @[JSON::Field(key: "FinishedAt")]
          property finished_at : Time?

          @[JSON::Field(key: "LastRestart")]
          property last_restart : Time?

          @[JSON::Field(key: "Restarts")]
          property restarts : UInt64

          @[JSON::Field(key: "StartedAt")]
          property started_at : Time?

          @[JSON::Field(key: "State")]
          property state : String

          @[JSON::Field(key: "TaskHandle")]
          property task_handle : Nil

          class Event
            include JSON::Serializable

            @[JSON::Field(key: "Details")]
            property details : Hash(String, String)

            @[JSON::Field(key: "DiskLimit")]
            property disk_limit : UInt64

            @[JSON::Field(key: "DisplayMessage")]
            property display_message : String

            @[JSON::Field(key: "DownloadError")]
            property download_error : String

            @[JSON::Field(key: "DriverError")]
            property driver_error : String

            @[JSON::Field(key: "DriverMessage")]
            property driver_message : String

            @[JSON::Field(key: "ExitCode")]
            property exit_code : UInt64

            @[JSON::Field(key: "FailedSibling")]
            property failed_sibling : String

            @[JSON::Field(key: "FailsTask")]
            property fails_task : Bool

            @[JSON::Field(key: "GenericSource")]
            property generic_source : String

            @[JSON::Field(key: "KillError")]
            property kill_error : String

            @[JSON::Field(key: "KillReason")]
            property kill_reason : String

            @[JSON::Field(key: "KillTimeout")]
            property kill_timeout : UInt64

            @[JSON::Field(key: "Message")]
            property message : String

            @[JSON::Field(key: "RestartReason")]
            property restart_reason : String

            @[JSON::Field(key: "SetupError")]
            property setup_error : String

            @[JSON::Field(key: "Signal")]
            property signal : UInt64

            @[JSON::Field(key: "StartDelay")]
            property start_delay : UInt64

            @[JSON::Field(key: "TaskSignal")]
            property task_signal : String

            @[JSON::Field(key: "TaskSignalReason")]
            property task_signal_reason : String

            @[JSON::Field(key: "Time", converter: Time::EpochNanosConverter)]
            property time : Time

            @[JSON::Field(key: "Type")]
            property type : String

            @[JSON::Field(key: "ValidationError")]
            property validation_error : String

            @[JSON::Field(key: "VaultError")]
            property vault_error : String
          end
        end

        class NetworkStatus
          include JSON::Serializable

          @[JSON::Field(key: "Address")]
          property address : String

          @[JSON::Field(key: "DNS")]
          property dns : Nil

          @[JSON::Field(key: "InterfaceName")]
          property interface_name : String
        end

        class RescheduleTracker
          include JSON::Serializable

          @[JSON::Field(key: "Events")]
          property events : Array(Event)

          class Event
            include JSON::Serializable

            @[JSON::Field(key: "Delay")]
            property delay : UInt64

            @[JSON::Field(key: "PrevAllocID")]
            property prev_alloc_id : UUID

            @[JSON::Field(key: "PrevNodeID")]
            property prev_node_id : UUID?

            @[JSON::Field(key: "RescheduleTime", converter: Time::EpochNanosConverter)]
            property reschedule_time : Time
          end
        end

        class Resources
          include JSON::Serializable

          @[JSON::Field(key: "CPU")]
          property cpu : UInt64

          @[JSON::Field(key: "Cores")]
          property cores : UInt64

          @[JSON::Field(key: "DiskMB")]
          property disk_mb : UInt64

          @[JSON::Field(key: "IOPS")]
          property iops : UInt64

          @[JSON::Field(key: "MemoryMB")]
          property memory_mb : UInt64

          @[JSON::Field(key: "MemoryMaxMB")]
          property memory_max_mb : UInt64
        end

        class Metrics
          include JSON::Serializable

          @[JSON::Field(key: "AllocationTime")]
          property allocation_time : UInt64

          @[JSON::Field(key: "ClassExhausted")]
          property class_exhausted : Nil

          @[JSON::Field(key: "ClassFiltered")]
          property class_filtered : Nil

          @[JSON::Field(key: "CoalescedFailures")]
          property coalesced_failures : UInt64?

          @[JSON::Field(key: "ConstraintFiltered")]
          property constraint_filtered : Hash(String, Int64)?

          @[JSON::Field(key: "DimensionExhausted")]
          property dimension_exhausted : Hash(String, Int64)?

          @[JSON::Field(key: "NodesAvailable")]
          property nodes_available : Hash(String, UInt64)

          @[JSON::Field(key: "NodesEvaluated")]
          property nodes_evaluated : UInt64

          @[JSON::Field(key: "NodesExhausted")]
          property nodes_exhausted : UInt64

          @[JSON::Field(key: "NodesFiltered")]
          property nodes_filtered : UInt64

          @[JSON::Field(key: "QuotaExhausted")]
          property quota_exhausted : Nil

          @[JSON::Field(key: "ScoreMetaData")]
          property score_meta_data : Array(ScoreMetaData)

          @[JSON::Field(key: "Scores")]
          property scores : Nil

          class ScoreMetaData
            include JSON::Serializable

            @[JSON::Field(key: "NodeID")]
            property node_id : UUID

            @[JSON::Field(key: "NormScore")]
            property norm_score : Float64

            @[JSON::Field(key: "Scores")]
            property scores : Hash(String, Float64)
          end
        end

        class AllocatedResources
          include JSON::Serializable

          @[JSON::Field(key: "Tasks")]
          property tasks : Hash(String, Task)
        end

        class Task
          include JSON::Serializable

          @[JSON::Field(key: "Cpu")]
          property cpu : Cpu

          @[JSON::Field(key: "Memory")]
          property memory : Memory

          class Cpu
            include JSON::Serializable

            @[JSON::Field(key: "CpuShares")]
            property cpu_shares : UInt64

            @[JSON::Field(key: "ReservedCores")]
            property reserved_cores : UInt64?
          end

          class Memory
            include JSON::Serializable

            @[JSON::Field(key: "MemoryMB")]
            property memory_mb : UInt64

            @[JSON::Field(key: "MemoryMaxMB")]
            property memory_max_mb : UInt64
          end
        end
      end
    end
  end
end
