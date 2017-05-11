require "udt/version"
require 'socket'
require 'json'

module String
  def chunk(string, size)
    string.scan(/.{1,#{size}}/)
  end
end

module Udt
  PACKET_SIZE = 1024

  def initialize(host, port)
    @host = host
    @port = port
    @tcp = TCPSocket.new(host, port)
    @udp = UDPSocket.new
  end

  def send(file_path)
    @data = {}
    read_file file_path, PACKET_SIZE do |chunk, index|
      @data[index] = chunk
    end
    send_command(:start, @data.size)
    Thread.new do
      until @data.empty?
        @data.each do |index, data|
          send_data index
        end
      end
    end
    while true
      command = wait_command
      case command[:name]
        when 'ack'
          command[:data].each do |data_index|
            @data.delete data_index
          end
          break if @data.empty?
      end
    end
  end

  def receive
    command = wait_command until command[:name] == 'start' # ????
    packets = command[:data]
    data = {}
    acks = Set.new
    thread = Thread.new do
      while true
        sleep 1
        send_acks! acks
      end
    end
    while true
      data_obj = wait_data
      data_chunk = data_obj[:data]
      index = data_obj[:index]
      data[index] = data_chunk
      acks << index
      break if data.size == packets
    end
    send_acks! acks
    thread.exit

    piece_together data
  end

  private

  def read_file(file_path, size)
    File.open(file_path, "rb") do |file|
      counter = 0
      while (buffer = file.read(size)) do
        yield buffer, counter
        counter += 1
      end
    end
  end

  def piece_together(data)
    data_string = ''
    for index in 0...data.size
      data_string << data[index]
    end
    data_string
  end

  def wait_command
    # {name: '', data: {}}
    JSON.parse(@tcp.recv(PACKET_SIZE))
  end

  def wait_data
    JSON.parse @udp.recv(PACKET_SIZE)
  end

  def send_command(command, data)
    json = {name: command, data: data}
    @tcp.send(JSON.stringify(json), 0)
  end

  def send_data(index)
    json = {data: @data[index], index: index}
    @udp.send(JSON.stringify(json), 0, @host, @port)
  end

  def send_acks!(acks)
    send_command(:ack, acks)
    acks.clear
  end
end
