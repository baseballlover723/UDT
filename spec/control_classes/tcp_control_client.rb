require 'socket'

class TCPControlClient
  include Client
  @socket
  @out_dir

  def initialize(host, port)
    @out_dir = './files_to_transfer/'
    @socket = TCPSocket.new(host, port)
  end

  def send(file_name)
    begin
      file_path = @out_dir + file_name

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
      @socket.close

    rescue Exception => e
      @socket.close
      raise e
    end
  end
end