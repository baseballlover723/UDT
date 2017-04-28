$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "udt"
$LOAD_PATH.unshift File.expand_path("../control_classes", __FILE__)
require "client"
require "server"
require "tcp_control_client"
require "udp_server"
require "udp_client"
