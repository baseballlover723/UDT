require 'benchmark/ips'
require 'json'
require 'set'

class Set
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


array = []
1000.times { |n| array << n }
150.times { array.delete_at 50 }
50.times { array.delete_at 175 }
75.times { array.delete_at 540 }
json = JSON.generate({name: 'command', data: array})

custom = 'command|' + array.join(',')
custom3 = '7command' + array.join(',')
custom4 = 'command' + array.join(',')
custom5 = 'command0-49,200-324,375-739,815-999'

# raw_command = String.new custom
# index = raw_command.index('|')
# command = raw_command[0...index]
# data = raw_command[(index+1)..-1]
# data = data.split(',').map(&:to_i)
#
# puts command
# puts data.inspect
#
# raw_command = String.new custom
# data = raw_command.split(',')
# command_name, data[0] = data[0].split('|')
# data.map!(&:to_i)
#
# puts command_name
# puts data.inspect
#
# raw_command = String.new custom3
# command_length = raw_command[0].to_i
# command_name = raw_command[1..command_length]
# data = raw_command[(command_length+1)..-1].split(',').map(&:to_i)
#
# puts command_name
# puts data.inspect
#
# raw_command = String.new custom4
# command_name = raw_command[0..7]
# data = raw_command[7..-1].split(',').map(&:to_i)
#
# puts command_name
# puts data.inspect
#
#
# raw_command = String.new custom5
# command_name = raw_command[0..7]
# data = []
# raw_command[7..-1].split(',').each do |string_range|
#   index = string_range.index('-')
#   data += (string_range[0..index].to_i..string_range[(index+1)..-1].to_i).to_a
# end
#
# puts command_name
# puts data.inspect

total_hash = {}
1000.times { |n| total_hash[n] = 0 }


to_remove1 = []
250.times { |n| to_remove1 << n + 250 }
range1 = (250..500)

# puts to_remove1.inspect
# puts range1.inspect

ranges = [(50..150), (450..653), (130..175), (750..800), (825..850), (775..840)]
hash = {}
ranges.each do |range|
  range.each do |n|
    found = false
    valid_keys = hash.keys.keep_if { |key| n > key }
    valid_keys.each do |start|
      finish = hash[start]
      found = true if n <= finish + 1
      hash[start] = n if (finish + 1) == n
    end
    hash[n] = n unless found
  end
end

puts hash.inspect

array = Set.new
ranges.each do |range|
  range.each do |n|
    array << n
  end
end

puts array.to_ranges.inspect

Benchmark.ips do |x|
  x.config(:time => 15, :warmup => 2)

  # x.report 'json' do
  #   hash = total_hash.clone
  #   raw_command = String.new json
  #   index = raw_command.index('}')
  #   next unless index
  #   raw_command = raw_command[0..index] unless raw_command.size + 1 == index
  #   begin
  #     command = JSON.parse(raw_command, symbolize_names: true)
  #   rescue JSON::ParserError => e
  #     puts 'FAILED!!!!!!!!!!!!!!!!!!!'
  #   end
  #   command[:name] == 'command'
  #   command[:data].each do |index|
  #     hash.delete index
  #   end
  #   command[:data].inspect
  # end

  # x.report 'custom1' do
  #   hash = total_hash.clone
  #   raw_command = String.new custom
  #   index = raw_command.index('|')
  #   command_name = raw_command[0..index]
  #   data = raw_command[index..-1]
  #   data = data.split(',').map(&:to_i)
  #   command_name == 'command'
  #   data.inspect
  # end
  #
  # x.report 'custom2' do
  #   hash = total_hash.clone
  #   raw_command = String.new custom
  #   data = raw_command.split(',')
  #   command_name, data[0] = data[0].split('|')
  #   data.map!(&:to_i)
  #   command_name == 'command'
  #   data.each do |index|
  #     hash.delete index
  #   end
  #   data.inspect
  # end
  #
  # x.report 'custom3' do
  #   hash = total_hash.clone
  #   raw_command = String.new custom3
  #   command_length = raw_command[0].to_i
  #   command_name = raw_command[1..command_length]
  #   data = raw_command[(command_length+1)..-1].split(',').map(&:to_i)
  #   command_name == 'command'
  #   data.each do |index|
  #     hash.delete index
  #   end
  #   data.inspect
  # end
  #
  # x.report 'custom4' do
  #   hash = total_hash.clone
  #   raw_command = String.new custom4
  #   command_name = raw_command[0..7]
  #   data = raw_command[7..-1].split(',').map(&:to_i)
  #   command_name == 'command'
  #   data.each do |index|
  #     hash.delete index
  #   end
  #   data.inspect
  # end

  x.report 'custom5.1' do
    hash = total_hash.clone
    raw_command = String.new custom5
    command_name = raw_command[0..7]
    data = []
    raw_command[7..-1].split(',').each do |string_range|
      index = string_range.index('-')
      data << (string_range[0..index].to_i..string_range[(index+1)..-1].to_i)
    end
    command_name == 'command'
    data.each do |range|
      range.each do |index|
        hash.delete index
      end
    end
    data.inspect
  end

  x.report 'custom5.2' do
    hash = total_hash.clone
    raw_command = String.new custom5
    command_name = raw_command[0..7]
    data = []
    raw_command[7..-1].split(',').each do |string_range|
      data << Range.new(*string_range.split('-', 2).map(&:to_i))
    end
    command_name == 'command'
    data.each do |range|
      range.each do |index|
        hash.delete index
      end
    end
    data.inspect
  end
  #
  # x.report 'to_range' do
  #   array = Set.new
  #   ranges.each do |range|
  #     range.each do |n|
  #       array << n
  #     end
  #   end
  #
  #   array.to_ranges
  # end
  #
  # x.report 'to_range1' do
  #   array = Set.new
  #   ranges.each do |range|
  #     range.each do |n|
  #       array << n
  #     end
  #   end
  #
  #   array.to_ranges
  # end
  #
  # x.report 'my to_range' do
  #   hash = {}
  #   ranges.each do |range|
  #     range.each do |n|
  #       found = false
  #       valid_keys = hash.keys.keep_if { |key| n > key }
  #       valid_keys.each do |start|
  #         finish = hash[start]
  #         found = true if n <= finish + 1
  #         hash[start] = n if (finish + 1) == n
  #       end
  #       hash[n] = n unless found
  #     end
  #   end
  # end

  x.compare!
end
