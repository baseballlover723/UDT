require 'socket'

class TCPControlClient
  include Client
  include Server
  PACKET_SIZE = 1024

  def initialize(host, port)
    @socket = TCPSocket.new(host, port)
  end

  def send(file_path)
    read_file(file_path, PACKET_SIZE) do |data, index|
      @socket.send(data, 0)
    end
    @socket.flush
    @socket.close_write
  end

  def receive
    conn = @socket
    total_content = ''
    thread = Thread.current
    thread[:ready] = false
    Thread.new do
      sleep 0.01
      thread[:ready] = true
    end
    conn.wait_readable
    while (content = conn.recv(PACKET_SIZE)) != ''
      total_content += content
    end
    conn.close
    total_content
  end
end
