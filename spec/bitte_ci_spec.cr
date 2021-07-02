require "./spec_helper"

describe BitteCI do
  # TODO: Write tests

  it "works" do
    socket_io = IO::Memory.new
    socket = HTTP::WebSocket.new(socket_io)
    control = BitteCI::ChannelControl.new
    channels = [] of Channel(String)

    BitteCI.start_control(control, channels)

    config = BitteCI::Config.new(
      public_url: URI.parse("http://127.0.0.1:9494"),
      db_url: URI.parse("postgres:localhost:5432/bitte_ci"),
      loki_url: URI.parse("http://127.0.0.1:3100"),
      nomad_url: URI.parse("http://127.0.0.1:4646"),
      frontend_path: "result",
      githubusercontent_url: URI.parse("http://127.0.0.1:8080")
    )

    conn = BitteCI::Connection.new(socket, control, config).run
    Fiber.yield
    channels.size.should eq(1)
  end
end
