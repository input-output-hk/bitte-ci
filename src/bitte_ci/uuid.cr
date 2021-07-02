require "uuid"

struct UUID
  def self.new(pull : JSON::PullParser)
    new pull.read_string
  end

  def to_json(builder : JSON::Builder)
    builder.string to_s
  end

  def to_json_object_key
    to_s
  end
end

class URI
  def to_json(builder : JSON::Builder)
    to_s.to_json(builder)
  end
end
