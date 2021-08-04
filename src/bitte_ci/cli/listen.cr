require "../cli"
require "../listener"

BitteCI.parse_options("listen", BitteCI::Listener::Config) do |config|
  BitteCI::Listener.listen(config)
end
