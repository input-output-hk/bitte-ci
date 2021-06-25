require "./spec_helper"

describe BitteCI do
  # TODO: Write tests

  it "works" do
    socket_io = IO::Memory.new
    socket = HTTP::WebSocket.new(socket_io)
    control = BitteCI::ChannelControl.new
    channels = [] of Channel(String)

    BitteCI.start_control(control, channels)

    conn = BitteCI::Connection.new(socket, control).run
    Fiber.yield
    channels.size.should eq(1)
  end
end
