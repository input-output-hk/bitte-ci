require "json"

module BitteCI
  class JobConfig
    include JSON::Serializable

    property ci : CI

    class CI
      include JSON::Serializable

      property version : UInt8
      property steps : Array(Step)
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
      property priority : UInt32 = 50
      property outputs : Array(String) = [] of String
      property env : Hash(String, String) = {} of String => String
    end
  end
end
