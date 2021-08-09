require "kemal"
require "json"
require "clear"
require "option_parser"
require "../*"

BitteCI.parse_options(
  BitteCI::Server::Config,
  BitteCI::Migrator::Config,
  BitteCI::Runner::Config,
  BitteCI::Listener::Config,
  BitteCI::Commander::Config,
  BitteCI::Preparator::Config,
)
