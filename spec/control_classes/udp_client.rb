require 'socket'
require 'timeout'

class UDPClient
  include Client
  include Server
  PACKET_SIZE = 1472
  TIMEOUT = 0.5

  def initialize(host, port)
    @socket = UDPSocket.new
    @host = host
    @port = port

  end

  def send(file_path)
    max = 0
    size = (File.size(file_path) / PACKET_SIZE.to_f).ceil
    size = size.to_s.ljust(6, ' ')
    # print ' packet numb: 0     /' + size
    
    read_file(file_path, PACKET_SIZE) do |data, index|
      max = index
      @socket.send(data, 0, @host, @port)
      # print "\b\b\b\b\b\b\b\b\b\b\b\b\b"
      # print "#{(index+1).to_s.rjust(6, ' ')}/#{size}"
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
    begin
      Timeout::timeout(2) do
        connection.wait_readable
      end
    rescue Timeout::Error
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
