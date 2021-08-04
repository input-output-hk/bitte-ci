require "../cli"
require "../server"

BitteCI.parse_options("server", BitteCI::Server::Config) do |config|
  Clear::SQL.init(config.postgres_url.to_s)
  BitteCI::Server.start(config)
  Kemal.config.port = config.port
  Kemal.config.host_binding = config.host
  Kemal.run
end
