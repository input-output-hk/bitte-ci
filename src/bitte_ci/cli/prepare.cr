require "../cli"
require "../preparator"

BitteCI.parse_options("prepare", BitteCI::Preparator::Config) do |config|
  BitteCI::Preparator.run(config)
end
