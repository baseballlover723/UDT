require 'socket'
require 'timeout'

class UDPClient
  include Client
  include Server
  PACKET_SIZE = 1024

  def initialize(host, port)
    @socket = UDPSocket.new
    @host = host
    @port = port

  end

  def send(file_path)
    read_file(file_path, PACKET_SIZE) do |data, index|
      @socket.send(data, 0, @host, @port)
    end
  end

  def receive
    connection = @socket
    if @host == 'localhost'
      connection = UDPSocket.new
      connection.bind(nil, @port)
    end
    connection.wait_readable
    total_content = ''
    begin
      Timeout::timeout(0.5) do
        while content = connection.recvfrom(PACKET_SIZE)
          content = content[0]
          total_content += content
        end
      end
    rescue Timeout::Error
    end
    total_content
  end
end
