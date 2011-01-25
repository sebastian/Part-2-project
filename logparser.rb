#!/usr/bin/env ruby

require 'csv'

# This is a utility that parses log files
# from the friend search dht network

class Request
  attr_accessor :start_time, :end_time, :nodes, :key

  def initialize(key)
    @key = key
    @nodes = 0
    @start_time = 0
    @end_time = 0
  end

  def add_data(data)
    key = data[0]
    time = data[1]
    node = data[2]
    action = data[3]

    self.nodes = self.nodes + 1
    self.start_time = time.to_i if action == "start_lookup"
    self.end_time = time.to_i if action == "end_lookup"
  end

  def to_s
    "#{@key};#{end_time - start_time};#{@nodes}\n"
  end

end

class LogParser
  def initialize(filename) 
    @requests = {}
    @filename = filename
  end

  def parse
    CSV.open(@filename, 'r', ';') do |record|
      key = record[0]
      request = @requests[key] ||= Request.new(key)
      request.add_data record
      @requests[key] = request
    end

    puts "Parsed out #{@requests.size} requests"
  end

  def output
    request_array.each do |request|
      print request
    end
  end

  def to_file(filename)
    File.open(filename, "w") do |f|
      request_array.each do |request|
          f.write request
      end
    end
  end

  private
  def request_array
    @requests.to_a.map {|key, request| request}
  end
end

if ARGV.size == 0 then
  puts "Please supply the name of the log file to parse"
  exit 1
end

filename = ARGV.first
logParser = LogParser.new(filename)
logParser.parse
if ARGV.size == 2 then
  outputFilename = ARGV[1]
  logParser.to_file(outputFilename)
else
  logParser.output
end
