require "../cli"
require "../migrator"

BitteCI.parse_options("migrate", BitteCI::Migrator::Config) do |config|
  BitteCI::Migrator.run(config)
end
