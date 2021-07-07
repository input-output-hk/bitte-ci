require "./spec_helper"

describe BitteCI do
  it "is configurable" do
    public_url = "http://example.com"
    loki_url = "http://loki"

    c = BitteCI::Config.configure do |config|
      ENV["BITTE_CI_LOKI_BASE_URL"] = loki_url
      config["nomad_token_file"] = File.join(__DIR__, "fixtures/nomad_token.fixture")

      config["public_url"] = public_url
      config["postgres_url"] = "postgres://localhost:5432/bitte_ci"
      config["nomad_base_url"] = "http://127.0.0.1:4646"
      config["frontend_path"] = "result"
      config["github_user_content_base_url"] = "http://127.0.0.1:8080"
      config["github_hook_secret"] = "secret"
      config["github_user"] = "hello"
      config["github_token"] = "there"
    end

    c.public_url.should eq(URI.parse(public_url))
    c.loki_base_url.should eq(URI.parse(loki_url))
    c.nomad_token.should eq(File.read(c.nomad_token_file.not_nil!))
  end

  it "works" do
    socket_io = IO::Memory.new
    socket = HTTP::WebSocket.new(socket_io)
    control = BitteCI::ChannelControl.new
    channels = [] of Channel(String)

    BitteCI.start_control(control, channels)

    final_config = BitteCI::Config.configure do |config|
      config["public_url"] = "http://127.0.0.1:9494"
      config["postgres_url"] = "postgres://localhost:5432/bitte_ci"
      config["loki_url"] = "http://127.0.0.1:3100"
      config["nomad_base_url"] = "http://127.0.0.1:4646"
      config["frontend_path"] = "result"
      config["github_user_content_base_url"] = "http://127.0.0.1:8080"
      config["github_hook_secret"] = "foobar"
      config["github_user"] = "hello"
      config["github_token"] = "there"
      config["nomad_token"] = "letmein"
    end

    conn = BitteCI::Connection.new(socket, control, final_config).run
    Fiber.yield
    channels.size.should eq(1)
  end
end
