require 'socket'
require 'timeout'

class UDPClient
  include Client
  include Server
  PACKET_SIZE = 1024
  TIMEOUT = 0.5

  def initialize(host, port)
    @socket = UDPSocket.new
    @host = host
    @port = port

  end

  def send(file_path)
    max = 0
    read_file(file_path, PACKET_SIZE) do |data, index|
      max = index
      @socket.send(data, 0, @host, @port)
    end
    @socket.flush unless @socket.closed?
    max + 1
  end

  def receive
    connection = @socket
    if @host == 'localhost'
      connection = UDPSocket.new
      connection.bind('localhost', @port)
    end
    thread = Thread.current
    thread[:ready] = false
    Thread.new do
      sleep 0.01
      thread[:ready] = true
    end
    begin
      Timeout::timeout(2) do
        connection.wait_readable
      end
    rescue Timeout::Error
      puts "FAILED!!!!!"
      return false
    end
    total_content = ''
    counter = -1
    while true
      begin
        Timeout::timeout(TIMEOUT) do
          content = connection.recvfrom(PACKET_SIZE)
          content = content[0]
          total_content += content
          counter += 1
        end
      rescue Timeout::Error
        break
      end
    end
    connection.close if @host == 'localhost'
    total_content
  end
end
