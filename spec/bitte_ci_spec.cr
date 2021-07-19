require "./spec_helper"

describe BitteCI do
  public_url = "http://example.com"
  loki_url = "http://loki"
  nomad_token_file = File.join(__DIR__, "fixtures/nomad_token.fixture")
  ENV["LOKI_BASE_URL"] = loki_url

  it "is configurable" do
    c = BitteCI::Server::Config.configure do |config|
      config["nomad_token_file"] = nomad_token_file
      config["frontend_path"] = "frontend"
      config["github_hook_secret"] = "foobar"
      config["github_token"] = "token"
      config["github_user_content_base_url"] = "http://127.0.0.1:8080"
      config["github_user"] = "user"
      config["nomad_datacenters"] = "dc1"
      config["postgres_url"] = "postgres://localhost:5432/bitte_ci"
      config["public_url"] = "http://example.com"
    end

    c.public_url.should eq(URI.parse(public_url))
    c.loki_base_url.should eq(URI.parse(loki_url))
    c.nomad_token.should eq(File.read(nomad_token_file))
  end

  it "works" do
    socket_io = IO::Memory.new
    socket = HTTP::WebSocket.new(socket_io)
    control = BitteCI::ChannelControl.new
    channels = [] of Channel(String)

    config = BitteCI::Server::Config.configure do |config|
      config["nomad_token_file"] = nomad_token_file
      config["frontend_path"] = "frontend"
      config["github_hook_secret"] = "foobar"
      config["github_token"] = "token"
      config["github_user_content_base_url"] = "http://127.0.0.1:8080"
      config["github_user"] = "user"
      config["nomad_datacenters"] = "dc1"
      config["postgres_url"] = "postgres://localhost:5432/bitte_ci"
      config["public_url"] = "http://example.com"
    end

    BitteCI::Server.new(config).start_control(control, channels)

    conn = BitteCI::Connection.new(socket, control, config).run
    Fiber.yield
    channels.size.should eq(1)
  end
end
