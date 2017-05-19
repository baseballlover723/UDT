require 'v2/udt/version'
require 'socket'
require 'json'
require 'colorize'
require 'thread'

class String
  def chunk(string, size)
    string.scan(/.{1,#{size}}/)
  end
end

class Set
  def to_s
    to_a.to_s
  end

  def to_ranges
    array = self.to_a.sort
    ranges = []
    if !array.empty?
      # Initialize the left and right endpoints of the range
      left, right = self.first, nil
      array.each do |obj|
        # If the right endpoint is set and obj is not equal to right's successor
        # then we need to create a range.
        if right && obj != right.succ
          ranges << Range.new(left, right)
          left = obj
        end
        right = obj
      end
      ranges << Range.new(left, right)
    end
    ranges
  end
end

class UDT_V2
  PACKET_SIZE = 1468 # ethernet MTU is 1500, Max datagram size is 1472, -4 to allow for 4 bytes at the front to indicate the index
  MAX_JSON_OVERHEAD = 20000
  ACK_WAIT = 0.25

  def initialize(host, port, verbose=false)
    @verbose = verbose
    @host = host
    @port = port
    @tcp = TCPSocket.new(host, port)
    @udp = UDPSocket.new
    @acks_mutex = Mutex.new

    if host == 'localhost'
      @local_hack = UDPSocket.new
      @local_hack.bind('localhost', @port)
    end
    print "\n" if @verbose
  end

  # max number of bytes that it can send is 6,305,011,990,528 (5,872 GB)
  def send(file_path)
    @data = {}
    read_file file_path, PACKET_SIZE do |chunk, index|
      @data[index] = chunk
    end
    @congestion_control_sleep_time = ACK_WAIT * 100.0 / @data.size
    send_command(:srt, @data.size)
    thread = Thread.new do
      wait_command('rdy')
      @data.each do |index, data|
        send_data index
      end
      until @data.empty?
        @data.each do |index, data|
          send_data index
          sleep @congestion_control_sleep_time
          break if @data.empty?
        end
      end
    end
    while true
      command_name, data = wait_command 'ack', 'fin'
      case command_name
        when 'ack'
          data.each do |data_index|
            @data.delete data_index
          end
          @last_acks = data.size
          @last_acks = 1 if @last_acks == 0
          @congestion_control_sleep_time = ACK_WAIT / 2.0 / @last_acks
          # print "packets to send: #{@data.size} last_acks: #{@last_acks} congestion_control_sleep_time: #{@congestion_control_sleep_time}\r"# if @verbose
          break if @data.empty?
        when 'fin'
          thread.exit
          break
      end
    end
    @local_hack.close if @host == 'localhost'
  end

  def receive
    command_name, packets = wait_command 'srt'
    # packets_str = packets.to_s.ljust(6, ' ')
    data = {}
    acks = Set.new
    send_command(:rdy)
    thread = Thread.new do
      (@local_hack || @udp).wait_readable
      until data.size == packets
        sleep ACK_WAIT
        send_acks! acks
      end
    end
    # print ' packet numb: 0     /' + packets_str
    # print_counter = 0
    until data.size == packets
      # print_counter += 1
      index, raw_data = wait_data

      # print "receiving data index: #{index.to_s.yellow}, data: '#{raw_data.cyan}'\n" if @verbose
      # print "receiving data index: #{index.to_s.yellow}, data: ''}'\n" if @verbose
      data[index] = raw_data
      # if print_counter == 100
      #   print_counter = 0
      #   print "\b\b\b\b\b\b\b\b\b\b\b\b\b"
      #   print "#{(data.size).to_s.rjust(6, ' ')}/#{packets_str}"
      # end
      @acks_mutex.synchronize do
        acks << index
      end
    end
    # print "\b\b\b\b\b\b\b\b\b\b\b\b\b"
    # print "#{(data.size).to_s.rjust(6, ' ')}/#{packets_str}"
    send_acks! acks
    thread.exit
    send_command(:fin)
    @local_hack.close if @host == 'localhost'
    @tcp.flush
    @tcp.close_write

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

  def encode_data(index, raw_data)
    binary_index = [index].pack('N')
    "#{binary_index}#{raw_data}"
  end

  def decode_data(encoded)
    index = encoded[0..3].unpack('N')[0]
    raw_data = encoded[4..-1]
    return index, raw_data
  end

  # use ranges and custom format
  def wait_command(*names)
    while true
      raw_command = @tcp.recv(PACKET_SIZE + MAX_JSON_OVERHEAD, Socket::MSG_PEEK) || '""' # werid multithreading json bug, sometimes is empty
      cmd_name = raw_command[0..2]
      if names.include? cmd_name
        return cmd_name, nil if raw_command.size <= 3
        end_index = raw_command.index("\0")
        next unless end_index
        data_str = raw_command[3...end_index]
        print 'received command ' + cmd_name + ' : ' + data_str + "\n" if @verbose
        @tcp.recv(data_str.bytesize + 4)
        data = nil
        case cmd_name
          when 'ack'
            data = Set.new
            return cmd_name, data if data_str.empty?
            data_str.split(',').each do |range_str|
              start, fin = *range_str.split('-', 2).map(&:to_i)
              start.upto(fin).each do |num|
                data << num
              end
            end
          when 'srt'
            data = data_str.to_i
        end
        return cmd_name, data
      else
        sleep 0.01
      end
    end
  end

  def wait_data
    udp = @local_hack || @udp
    decode_data udp.recv(PACKET_SIZE + MAX_JSON_OVERHEAD)
  end

  def send_command(command, data=nil)
    to_send = "#{command}#{data}\0"
    print "send command #{to_send}\n" if @verbose
    @tcp.send(to_send, 0)
    @tcp.flush
  end

  def send_data(index)
    data = @data[index]
    encoded = encode_data index, data
    # print "sending data index #{index.to_s.yellow}, data: '#{data.green}'\n" if @verbose
    # print "sending data index #{index.to_s.yellow}, data: ''\n" if @verbose
    @udp.send(encoded, 0, @host, @port)
    # sleep 0.001
  end

  def send_acks!(acks)
    @acks_mutex.synchronize do
      return if acks.empty? && @sent_empty_acks_last
      arr_ranges = acks.to_ranges
      string_ranges = arr_ranges.map() do |range|
        "#{range.first}-#{range.last}"
      end.join(',')
      send_command(:ack, string_ranges)
      @sent_empty_acks_last = acks.empty?
      acks.clear
    end
  end
end
