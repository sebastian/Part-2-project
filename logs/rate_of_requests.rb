#!/usr/bin/env ruby

require 'csv'

# This parser parses log files of a particular type:
# Logfiles for runs where everything is fixed over a given time
# interval. The number of hosts and nodes and rate is fixed,
# and the experiment is run for a particular amount of time.

class Request
  attr_reader :start_time, :data

  def initialize(key)
    @key = key
    @node_count = 0
    @start_time = 0
    @end_time = 0
    @data = 0
    @time_seen = nil
    @success = false
    @start_node = ""
    @data_node = ""
  end

  def add_data(data)
    type = data[0]

    case type
    when "data"
      # data;lookup;bits;key;time
      # data;success;key;time
      type = data[1]
      case type
      when "lookup"
        @data += data[2].to_i
      when "success"
        @success = true
      end
    when "act"
      # act;key;time;nodeId;action_type
      key = data[1]
      time = data[2].to_i
      node = data[3]
      action = data[4]
    
      @start_node = node if action == "start_lookup"
      @data_node = node if action == "lookup_datastore"
      @node_count += 1 if action == "route"
      @start_time = time if action == "start_lookup"
      @end_time = time if action == "end_lookup"
    end

  end

  def is_valid_for_start_time?(base_time)
    start_time > base_time
  end

  def is_valid?
    @success && has_start_time && has_end_time
  end

  def lat
    @end_time - @start_time
  end

  def nodes
    @node_count
  end

  def has_start_time
    @start_time != 0
  end

  def has_end_time
    @end_time != 0
  end

  def <=>(other_request)
    return -1 if @start_time < other_request.start_time
    return 0 if @start_time == other_request.start_time
    1
  end
end

class LogParser
  def initialize(filename) 
    @requests = {}
    @filename = filename
    @control_messages = []
    @total_bandwidth = 0

    @start_metadata = {}
    @end_metadata = {}
  end

  def parse
    CSV.open(@filename, 'r', ';') do |record|

      case record[0]
      when "ctrl"
        # ctrl;start;time;host_count;node_count
        # ctrl;end;time;host_count;node_count
        type = record[1]
        time = record[2].to_i
        host_count = record[3].to_i
        node_count = record[4].to_i
        data = {
            :nodes => node_count,
            :hosts => host_count,
            :time => time
        }
        @start_metadata = data if type == "start"
        @end_metadata = data if type == "end"

      when "data"
        # data;state;bits;time
        # data;lookup;bits;key;time
        # data;success;key;time

        type = record[1]
        case type
        when "lookup"
          key = record[3]
          time = record[4]
          add_to_request(key, time, record) 
        when "success"
          key = record[2]
          time = record[3]
          add_to_request(key, time, record) 
        end
        @total_bandwidth += record[2].to_i

      when "act"
        # act;key;time;nodeId;action_type
        key = record[1]
        time = record[2]
        add_to_request(key, time, record)

      end
    end

    puts "Parsed out #{@requests.size}"
  end

  def output
    puts "out of luck buddy... you need an output filename too. This feature is no longer supported"
  end

  def bin_requests(reqs, base_time)
    # Bin the requests per second
    bins = {}
    reqs = reqs.to_a.map { |k,v| v }
    good_reqs = reqs.select {|r| r.is_valid_for_start_time?(base_time) }
    good_reqs.each do |request|
      # Bin them by 10th of a second
      bin = request.start_time / 500
      bins[bin] = [] unless bins[bin]
      bins[bin] << request
    end
    bins.to_a.sort.map {|b,r| r}
  end

  def to_file(filename)
    base_time = @start_metadata[:time]
    binned_requests = bin_requests(@requests, base_time)

    File.open("#{filename}_rate_against_time.csv", "w") do |file|
      file.write "# Time Rate RateSuccess RateFail\n"
      binned_requests.each_index do |index|
        bin = binned_requests[index]
        valid_requests = bin.select {|r| r.is_valid? }
        rate = bin.length
        num_valid = valid_requests.length
        num_failed = rate - num_valid
        file.write "#{index} #{rate * 2} #{num_valid * 2} #{num_failed * 2}\n"
      end
    end
  end

  private
  def add_to_request(key, time, data)
    master_key = "#{key}#{time.to_i / 10000}"
    request = @requests[master_key] ||= Request.new(master_key)
    request.add_data data
    @requests[master_key] = request
  end
end

if ARGV.size != 2 then
  puts "Please supply the name of the log file to parse, the name prefix of the output, rate and dht name"
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
