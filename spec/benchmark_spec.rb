require 'spec_helper'
require 'active_support'
require 'active_support/number_helper'
require 'benchmark'
require 'axlsx'
require 'axlsx_styler'

Thread.abort_on_exception = true
ActiveSupport::Deprecation.silenced = true

def stfu
  begin
    orig_stderr = $stderr.clone
    orig_stdout = $stdout.clone
    $stderr.reopen File.new('/dev/null', 'w')
    $stdout.reopen File.new('/dev/null', 'w')
    retval = yield
  rescue Exception => e
    $stdout.reopen orig_stdout
    $stderr.reopen orig_stderr
    raise e
  ensure
    $stdout.reopen orig_stdout
    $stderr.reopen orig_stderr
  end
  retval
end

class Host
  attr_accessor :name, :address

  def initialize(name, address)
    @name = name
    @address = address
  end
end

class TestFile
  attr_accessor :iterations

  def initialize(file_path, iterations)
    @file = File.new(file_path)
    @iterations = iterations
  end

  def name
    File.basename @file
  end

  def size
    ActiveSupport::NumberHelper.number_to_human_size(@file.size, {precision: 4, strip_insignificant_zeros: false})
  end
end

class Protocol
  attr_accessor :name, :server, :client

  def initialize(name, server, client)
    @name = name
    @server = server
    @client = client
  end
end

class UDTTimes
  attr_accessor :version

  def initialize
    @versions = {}
    VERSIONS.each do |version|
      @versions[version] = {}
    end
  end
end

class Result
  attr_accessor :host, :file, :udp_time, :tcp_time, :udt_times

  def initialize(host, file)
    @host = host
    @file = file
    @udt_times = {} # {version: {ack: time}}
    VERSIONS.each do |version|
      acks = {}
      ACK_TIMES.each do |ack_time|
        acks[ack_time] = 'not yet run'
      end
      @udt_times[version] = acks

    end

  end
end

PORT = 3030
# HOSTS = [Host.new('Local', 'localhost'), Host.new('LAN', 'overmind.party'), Host.new('Internet', 'ec2-54-179-177-145.ap-southeast-1.compute.amazonaws.com')]
# HOSTS = [Host.new('Local', 'localhost'), Host.new('Internet', 'ec2-54-179-177-145.ap-southeast-1.compute.amazonaws.com')]
HOSTS = [Host.new('Local', 'localhost')]
# HOSTS = [Host.new('LAN', 'overmind.party')]
# HOSTS = [Host.new('Internet', 'ec2-54-179-177-145.ap-southeast-1.compute.amazonaws.com')]
# FILES = [TestFile.new('spec/test_files/tiny.txt', 100), TestFile.new('spec/test_files/small.jpg', 100), TestFile.new('spec/test_files/medium.jpg', 50), TestFile.new('spec/test_files/large.mp4', 10), TestFile.new('spec/test_files/xlarge.mp4', 5)]
FILES = [TestFile.new('spec/test_files/tiny.txt', 20), TestFile.new('spec/test_files/small.jpg', 20), TestFile.new('spec/test_files/medium.jpg', 20), TestFile.new('spec/test_files/large.mp4', 5), TestFile.new('spec/test_files/xlarge.mp4', 1)]
# FILES = [TestFile.new('spec/test_files/tiny.txt', 100), TestFile.new('spec/test_files/small.jpg', 100), TestFile.new('spec/test_files/medium.jpg', 50)]
# FILES = [TestFile.new('spec/test_files/tiny.txt', 5), TestFile.new('spec/test_files/small.jpg', 5)]
# FILES = [TestFile.new('spec/test_files/small.jpg', 1)]
# FILES = [TestFile.new('spec/test_files/tiny.txt', 10)]
# FILES = [TestFile.new('spec/test_files/medium.jpg', 1)]
# FILES = [TestFile.new('spec/test_files/large.mp4', 1)]
VERSIONS = [UDT_V1, UDT_V2]
# VERSIONS = [UDT_V2]
# ACK_TIMES = [0.05, 0.10, 0.15, 0.20, 0.25]
ACK_TIMES = [0.05, 0.25, 0.5]
# ACK_TIMES = [0.05]

def update_time(results, close=false)
  p = Axlsx::Package.new
  p.use_shared_strings = true

  p.workbook do |wb|
    styles = wb.styles
    title = styles.add_style :sz => 13, :b => true, :u => true, :alignment => {:horizontal => :center}
    center = styles.add_style :sz => 15, :b => true, :u => true, :alignment => {:horizontal => :center}
    box = styles.add_style(border: {style: :thick, color: 'F000000'})
    default = styles.add_style :border => Axlsx::STYLE_THIN_BORDER, :alignment => {:horizontal => :center}
    percent = styles.add_style(:format_code => '[GREEN]0.00%;-[RED]0.00%', :alignment => {:horizontal => :left, indent: 1})

    wb.add_worksheet(name: 'Benchmark results') do |ws|
      udt_version_row = ['', '', 'Avg Time (sec)', '']
      VERSIONS.each do |version|
        udt_version_row += ["UDT v#{version::VERSION} * Avg Time (sec)"] + Array.new(ACK_TIMES.size - 1, '*')

        udt_version_row << 'Best'
        udt_version_row << 'Fastest'
        udt_version_row << '% Faster'
      end
      ws.add_row udt_version_row, style: center
      ws.merge_cells ws.rows.first.cells[(2..3)]
      VERSIONS.size.times do |numb|
        start = 4 + numb * (ACK_TIMES.size + 3)
        finish = start + ACK_TIMES.size
        ws.merge_cells ws.rows.first.cells[(start...finish)]
      end

      title_row = ['Host', 'File', 'UDP', 'TCP']
      VERSIONS.size.times do
        ACK_TIMES.each do |ack_time|
          title_row << ack_time.to_s + ' ACK'
        end
        title_row << 'ACK Time'
        title_row << 'Time'
        title_row << 'Than TCP'
      end
      ws.add_row title_row, style: title
      results.each do |host, files|
        files.values.each do |result|
          widths = [10, 30, 10, 10]
          VERSIONS.size.times do
            ACK_TIMES.size.times do
              widths << 10
            end
            widths << 10
            widths << 10
            widths << 11
          end
          data = [host.name, "#{result.file.name} (#{result.file.size}) (#{result.file.iterations} times)", result.udp_time, result.tcp_time]
          result.udt_times.each do |version, ack_times|
            ack_times.each do |ack_time, time|
              data << time
            end
            times = ack_times.values.select { |time| time.is_a? Numeric }
            best_upt_time = times.min
            best_ack_time = ack_times.min_by { |k, v| v.is_a?(Numeric) ? v : Float::INFINITY }.first
            data << best_ack_time.to_s + ' sec'
            data << best_upt_time
            percentage = 0
            percentage = (result.tcp_time / best_upt_time) - 1 if result.tcp_time && best_upt_time
            data << percentage
          end

          styles = [nil, nil, nil, nil]
          VERSIONS.size.times do
            styles += Array.new(ACK_TIMES.size + 2, nil)
            styles << percent
          end
          ws.add_row data, widths: widths, style: styles
        end
        ws.add_row Array.new(4 + (ACK_TIMES.size + 3) * VERSIONS.size, '')
      end
      y_start = 1
      y_end = ws.rows.size - 1
      ws.add_border "C#{y_start}:D#{y_end}", {style: :thick}
      VERSIONS.size.times do |numb|
        start_offset = numb * (ACK_TIMES.size + 3)
        x_start = 'E'
        start_offset.times { x_start = x_start.next }

        x_end = x_start
        (ACK_TIMES.size + 2).times { x_end = x_end.next }

        y_start = 1
        y_end = ws.rows.size - 1
        ws.add_border "#{x_start}#{y_start}:#{x_end}#{y_end}", {style: :thick}
      end
    end
  end
  begin
    system('wmctrl -c libreoffice') and puts 'closing excel' or sleep 0.15 if close && File.exists?('.~lock.benchmark.xlsx#')
    p.serialize 'benchmark.xlsx'
  rescue
    if close && ENV['BASH_ON_UBUNTU_ON_WINDOWS']
      puts 'closing excel'
      system 'cmd.exe /c taskkill /IM excel.exe'
      sleep 0.05
      begin
        p.serialize 'benchmark.xlsx'
      rescue
        sleep 0.15
        p.serialize 'benchmark.xlsx'
      end
    end
  end
end

describe 'Benchmark' do
  def clear_files
    Dir['./spec/received_files/*'].each do |file|
      begin
        File.delete(file)
      rescue Errno::EIO
        sleep 0.1
        File.delete(file)
      end
    end
  end

  first = true

  before(:each) do
    print "                                                                                        \r"
    sleep 5 unless first
    first = false
  end

  after(:each) do
    Thread.list.each do |thread|
      thread.exit unless thread == Thread.current
    end
    print "                                                                                        \r"
  end

  results = {}
  ITERATION_SLEEP = 2.5

  HOSTS.each do |host|
    context "Host: #{host.name}" do
      FILES.each do |file|
        context "File: #{file.name} (#{file.size})" do
          # it 'correctly sends the file using TCP' do
          #   file_name = file.name
          #   recieved_data = nil
          #   time = 0.0
          #   iterations = 0
          #   while iterations < file.iterations
          #     clear_files
          #     print "\rTCP iteration: #{iterations} / #{file.iterations}"
          #     client, thread = nil
          #     time1 = Benchmark.measure do
          #       client = TCPControlClient.new host.address, 3030
          #       thread = Thread.new do
          #         recieved_data = client.receive
          #       end
          #     end.real
          #     sleep 0.001 until thread[:ready]
          #     time2 = Benchmark.measure do
          #       client.send('spec/test_files/' + file_name)
          #       thread.join
          #     end.real
          #     next unless recieved_data
          #     File.open('spec/received_files/' + file_name, 'wb') { |file| file.write(recieved_data) }
          #     time += time1 + time2
          #     iterations += 1
          #     sleep ITERATION_SLEEP
          #     expect(FileUtils.identical?('spec/test_files/' + file_name, 'spec/received_files/' + file_name)).to be_truthy, 'received file is different than sent file'
          #   end
          #
          #   results[host] = {} unless results.has_key? host
          #   results[host][file_name] = Result.new(host, file) unless results[host].has_key? file_name
          #   result = results[host][file.name]
          #   result.tcp_time = time.real / file.iterations
          #   update_time results
          #   print "\r"
          # end

          it 'correctly sends the file using UDP' do
            file_name = file.name
            time = 0.0
            iterations = 0
            while iterations < file.iterations
              clear_files
              print "\rUDP iterations: #{iterations} / #{file.iterations}"
              client = nil
              time1 = Benchmark.measure do
                client = UDPClient.new host.address, 3030
                fork do
                  recieved_data = client.receive
                  File.open('spec/received_files/' + file_name, 'wb') { |file| file.write(recieved_data) }
                end
              end.real
              sleep 0.01
              time2 = Benchmark.measure do
                client.send('spec/test_files/' + file_name)
                Process.wait
              end.real
              # next unless recieved_data
              time += time1 + time2
              iterations += 1
              expect(File.exist? 'spec/received_files/' + file_name).to be_truthy, 'did not create file'
              expect(File.zero? 'spec/received_files/' + file_name).to be_falsey, 'file is empty'
              sleep ITERATION_SLEEP
            end

            results[host] = {} unless results.has_key? host
            results[host][file_name] = Result.new(host, file) unless results[host].has_key? file_name
            result = results[host][file.name]
            result.udp_time = (time.real - UDPClient::TIMEOUT * (file.iterations)) / (file.iterations)
            update_time results
            print "\r"
          end

          # VERSIONS.each do |udt_class|
          #   context "UDT v#{udt_class::VERSION}" do
          #     ACK_TIMES.each do |ack_time|
          #       it "correctly sends the file with #{ack_time} ack_time" do
          #         stfu { udt_class::ACK_WAIT = ack_time }
          #         file_name = file.name
          #         recieved_data = nil
          #         time = 0.0
          #         iterations = 0
          #         while iterations < file.iterations
          #           clear_files
          #           print "\rUDT (#{ack_time} ACK time) iteration: #{iterations} / #{file.iterations}"
          #           client, thread = nil
          #           time1 = Benchmark.measure do
          #             client = udt_class.new host.address, 3030#, true
          #             thread = Thread.new do
          #               recieved_data = client.receive
          #             end
          #           end.real
          #           sleep 0.001 until thread[:ready]
          #           time2 = Benchmark.measure do
          #             client.send('spec/test_files/' + file_name)
          #             thread.join
          #           end.real
          #           next unless recieved_data
          #           time += time1 + time2
          #           iterations += 1
          #           File.open('spec/received_files/' + file_name, 'wb') { |file| file.write(recieved_data) }
          #           expect(FileUtils.identical?('spec/test_files/' + file_name, 'spec/received_files/' + file_name)).to be_truthy, 'received file is different than sent file'
          #           sleep ITERATION_SLEEP
          #         end
          #
          #         results[host] = {} unless results.has_key? host
          #         results[host][file_name] = Result.new(host, file) unless results[host].has_key? file_name
          #         result = results[host][file.name]
          #         result.udt_times[udt_class][ack_time] = time.real / file.iterations
          #         update_time results
          #         print "\r"
          #       end
          #     end
          #   end
          # end
        end
      end
    end
  end

  after(:all) do
    update_time results, true
    file_to_open = "./benchmark.xlsx"
    puts 'opening excel'
    system ENV['BASH_ON_UBUNTU_ON_WINDOWS'] ? "cmd.exe /c start #{file_to_open}" : "nohup xdg-open #{file_to_open} &"
  end
end
