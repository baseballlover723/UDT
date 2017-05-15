$LOAD_PATH.unshift File.expand_path("../../lib/v1", __FILE__)
require "udt_v1"
$LOAD_PATH.unshift File.expand_path("../control_classes", __FILE__)
require "client"
require "server"
require "tcp_control_client"
require "udp_client"
RSpec.configure do |c|
  c.fail_fast = true
end
