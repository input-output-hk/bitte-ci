require "./simple_config"

module BitteCI
  class Artificer
    struct Config
      include SimpleConfig::Configuration
    end

    def initialize
    end
  end
end
