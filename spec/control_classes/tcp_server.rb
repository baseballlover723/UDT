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

      loop do

        total_content += conn.recv(1048)

      end

      conn.close
      return total_content

    rescue

      conn.close
      return total_content

    end

  end
end
