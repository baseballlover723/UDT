class UDPServer
  include Server
  def initialize(port); end
  def receive
    yield 'file'
  end
end
