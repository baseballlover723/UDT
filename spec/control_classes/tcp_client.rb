require 'socket'

class TCPClient
  include Client
  @socket
  @out_dir

  def initialize(host, port)

    @out_dir = './files_to_transfer/'

    @cannot_start = false

    begin
      @socket = TCPSocket.new(host, port)
    rescue
      @cannot_start = true
      puts('Could not make connection')
    end

  end

  def send(file_name)

    begin

      if @cannot_start
        return false
      end

      file_path = @out_dir + file_name

      unless File.exists?(file_path)
        @socket.close
        return false
      end

      total_file_contents = ''

      begin
        file = File.open(file_path, 'r')
        total_file_contents = file.read
      rescue
        @socket.close
        return false
      end

      @socket.write(total_file_contents)

      @socket.close
      return true

    rescue

      raise RuntimeError, 'TCP connection got borked hard'

    end

  end

end