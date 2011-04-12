#!/usr/bin/env ruby

require 'csv'

# This parser parses log files of a particular type:
# Logfiles for runs where everything is fixed over a given time
# interval. The number of hosts and nodes and rate is fixed,
# and the experiment is run for a particular amount of time.

class Request
  attr_reader :start_time, :data, :success

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

  def is_valid?
    success && has_start_and_end_time
  end

  def <=>(other_request)
    return -1 if @start_time < other_request.start_time
    return 0 if @start_time == other_request.start_time
    1
  end

  def lat
    @end_time - @start_time
  end

  def nodes
    @node_count
  end

  def has_start_and_end_time
    @start_time != 0 && @end_time != 0
  end

  def is_valid_for_start_time?(base_time)
    start_time > base_time
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
    # The CSV reader runs into problems with my data at times
    File.open(@filename, 'r') do |file|
      while line = file.gets
        record = line.chomp.split(";")

        message_type = record[0]

        case message_type
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
          @end_metadata = data if type == "done"

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
    end

    puts "Parsed out #{@requests.size}"
  end

  def output
    puts "out of luck buddy... you need an output filename too. This feature is no longer supported"
  end

  def to_file(filename)
    # Create a directory for the result, if it doesn't already exist
    dir_name = "output/#{filename}"
    Dir.mkdir(dir_name) unless File.directory?(dir_name)

    ok_requests = valid_requests

    output_metric(ok_requests, :nodes, "Nodes", "nodes_against_time", dir_name)

    output_metric(ok_requests, :lat, "Latency", "latency_against_time", dir_name)

    total_num_req = @requests.size
    File.open("#{dir_name}/num_requests.txt", "w") do |file|
      file.write "#{total_num_req}"
    end

    File.open("#{dir_name}/meta_data.txt", "w") do |file|
      num_good_req = ok_requests.size
      num_bad_req = total_num_req - num_good_req

      file.write "Experimental stats:\n"
      file.write "-------------------\n"
      file.write "hosts start:    #{@start_metadata[:hosts]}\n"
      file.write "hosts end:      #{@end_metadata[:hosts]}\n"
      file.write "nodes start:    #{@start_metadata[:nodes]}\n"
      file.write "nodes end:      #{@end_metadata[:nodes]}\n"
      file.write "runtime:        #{normalized_time / 60000}\n"
      file.write "samples:        #{total_num_req}\n"
      file.write "good samples:   #{num_good_req}\n"
      file.write "bad samples:    #{num_bad_req}\n"

      file.write "\nOf all the good samples\n"
      file.write "-------------------\n"
      req_vals = ok_requests.map {|r| r.lat}
      sample_average = average_value(req_vals)
      sample_standard_deviation = standard_deviation(req_vals)
			sample_size = req_vals.size
      # To 95% confidence
			confidence = 0
      confidence = 1.96 * sample_standard_deviation / Math.sqrt(sample_size) if sample_size > 0
      file.write "Sample size:    #{sample_size}\n"
      file.write "Sample average: #{sample_average}\n"
      file.write "Sample stdev:   #{sample_standard_deviation}\n"
      file.write "95% conf pm:    #{confidence}\n"
    end
  end

  private
  def output_metric(ok_requests, metric, metric_name, file_ext, dir_name)
    File.open("#{dir_name}/#{file_ext}.csv", "w") do |file|
      file.write "Time #{metric_name}\n"
      
      base_time = @start_metadata[:time]

      ok_requests.each do |request|
        time = request.start_time - base_time
        file.write "#{time} #{request.send(metric)}\n" unless time < 0
      end
    end
  end

  # Returns time rounded to a whole minute in ms
  def normalized_time
    start_time = @start_metadata[:time]
    end_time = @end_metadata[:time]
    t = end_time - start_time
    length = Math::log10(t).to_i
    msd = (t / (10 ** length).to_f).round
    return msd * (10 ** length)
  end

  def valid_requests
    @requests.to_a.select {|key, request| 
      request.is_valid?
    }.map {|key, request| request}
  end

  def min_max_node_count(requests)
    min = 1000
    max = 0
    requests.each do |request|
      min = request.nodes if request.nodes < min
      max = request.nodes if request.nodes > max
    end
    [min, max]
  end

  def valid_requests_for_node_count(requests, nodecount)
    requests.select {|request| request.nodes == nodecount }
  end

  def add_to_request(key, time, data)
    master_key = "#{key}#{time.to_i / 10000}"
    request = @requests[master_key] ||= Request.new(master_key)
    request.add_data data
    @requests[master_key] = request
  end

  def average_value(values)
    sum = 0
    values.each do |value|
      sum += value
    end
    return sum / values.size if values.size > 1
    0
  end

  def variance(population)
    n = 0
    mean = 0.0
    s = 0.0
    population.each { |x|
      n = n + 1
      delta = x - mean
      mean = mean + (delta / n)
      s = s + delta * (x - mean)
    }
    return s / (n-1) if n > 1
    return s
  end
     
  # calculate the standard deviation of a population
  # accepts: an array, the population
  # returns: the standard deviation
  def standard_deviation(population)
    Math.sqrt(variance(population))
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
