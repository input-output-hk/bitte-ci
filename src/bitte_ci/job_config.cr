require "json"

module BitteCI
  class JobConfig
    include JSON::Serializable

    property ci : CI

    class CI
      include JSON::Serializable

      property version : UInt8
      property steps : Hash(String, Step)
    end

    class Step
      include JSON::Serializable

      property label : String
      property command : String | Array(String)
      property enable : Bool
      property flakes : Hash(String, Array(String))
      property vault : Bool
      property cpu : UInt32 = 100
      property memory : UInt32 = 300
      property outputs : Array(String) = [] of String
      property env : Hash(String, String) = {} of String => String
      property lifecycle : String?
      property sidecar : Bool?
      property after : Array(String) = [] of String
      property term_timeout : UInt64 = 1800
      property kill_timeout : UInt64 = 2100

      def initialize(
        @label,
        @command,
        @enable,
        @vault,
        @cpu,
        @memory,
        @lifecycle,
        @sidecar,
        @after = [] of String,
        @flakes = {} of String => Array(String),
        @outputs = [] of String,
        @env = {} of String => String
      )
      end
    end
  end
end
