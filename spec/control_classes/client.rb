module Client
  def initialize(host, port)
    raise 'not implemented'
  end
  
  def send(file)
    raise 'not implemented'
  end

  def read_file(file_path, size)
    File.open(file_path, "rb") do |file|
      counter = 0
      while (buffer = file.read(size)) do
        yield buffer, counter
        counter += 1
      end
    end
  end
end
