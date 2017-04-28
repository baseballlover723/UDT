require 'socket'

class TCPControlServer
  include Server
  @server

  def initialize(port)
    @server = TCPServer.new('0.0.0.0', port)
  end

  def receive
    conn = @server.accept
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
