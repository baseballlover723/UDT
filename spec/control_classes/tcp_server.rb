class TCPServer
  include Server
  def initialize(port); end
  def receive
    yield 'file'
  end
end
