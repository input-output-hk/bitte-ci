require "json"

struct Time
  def self.unix_ns(nanoseconds : Int64) : Time
    s = (nanoseconds // NANOSECONDS_PER_SECOND) + UNIX_EPOCH.total_seconds
    ns = (nanoseconds % NANOSECONDS_PER_SECOND).to_i
    utc(seconds: s, nanoseconds: ns)
  end

  def to_unix_ns : Int64
    to_unix * NANOSECONDS_PER_SECOND + nanosecond
  end

  module EpochNanosConverter
    def self.from_json(value : JSON::PullParser) : Time
      Time.unix_ns(value.read_int)
    end

    def self.to_json(value : Time, json : JSON::Builder)
      json.number(value.to_unix_ns)
    end
  end
end
