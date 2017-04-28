require 'socket'

class TCPControlClient
  include Client
  include Server
  @socket

  def initialize(host, port)
    @socket = TCPSocket.new(host, port)
  end

  def send(file_path)
    begin
      unless File.exists?(file_path)
        @socket.close
        raise Exception, 'File does not exist'
      end

      total_file_contents = ''
      begin
        file = File.open(file_path, 'r')
        total_file_contents = file.read
      rescue Exception => e
        @socket.close
        raise e
      end

      @socket.write(total_file_contents)
      @socket.close_write

    rescue Exception => e
      @socket.close
      raise e
    end
  end

  def receive
    conn = @socket
    total_content = ''
    begin
      while (content = conn.recv(1024)) != ''
        total_content += content
      end
      conn.close
      return total_content
    rescue Exception => e
      conn.close
      raise e
    end
  end
end
