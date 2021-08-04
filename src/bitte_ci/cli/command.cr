require "../cli"
require "../commander"

BitteCI.parse_options("command", BitteCI::Commander::Config) do |config|
  BitteCI::Commander.run(config)
end
