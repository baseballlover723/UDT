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

      while (content = conn.recv(1048)) != ''

        total_content += content

      end

      conn.close
      return total_content

    rescue

      raise RuntimeError, 'TCP connection got borked hard'

    end

  end
end
