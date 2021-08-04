require "../cli"
require "../runner"

BitteCI.parse_options("queue", BitteCI::Runner::Config) do |config|
  arg = ARGV[0]? ? File.read(ARGV[0]) : STDIN
  BitteCI::Runner.run(arg, config)
end
