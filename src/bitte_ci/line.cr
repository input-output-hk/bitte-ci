require "json"
require "./time"
require "./uuid"

module BitteCI
  module Listener
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
      }

      @[JSON::Field(key: "Topic")]
      property topic : String

      @[JSON::Field(key: "Namespace")]
      property namespace : String
    end

    class Allocation < Event
      @[JSON::Field(key: "Payload")]
      property payload : AllocationPayload
    end

    class AllocationPayload
      include JSON::Serializable

      @[JSON::Field(key: "Allocation")]
      property allocation : AllocationPayloadAllocation
    end

    class AllocationPayloadAllocation
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

        @[JSON::Field(key: "LastRestart", converter: Time::EpochNanosConverter)]
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
          property exit_code : Int32

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
          property signal : Int32

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
        property constraint_filtered : Nil

        @[JSON::Field(key: "DimensionExhausted")]
        property dimension_exhausted : Nil

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
