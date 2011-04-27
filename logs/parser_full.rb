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

  def to_file(filename, rate, dht)
    # Create a directory for the result, if it doesn't already exist
    dir_name = "output/#{filename}"
    Dir.mkdir(dir_name) unless File.directory?(dir_name)

    ok_requests = valid_requests

    shared_title = "\\n#{@start_metadata[:hosts]} hosts running a total of #{@start_metadata[:nodes]} nodes.\\n" +
                   "Request rate per host: #{rate}/s."

    output_metric(ok_requests, :nodes, "Nodes", "nodes_against_time", dir_name,
                  "Number of nodes involved in a lookup against time for #{dht}." + shared_title)

    output_metric(ok_requests, :lat, "Latency", "latency_against_time", dir_name, 
                  "Latency against time for #{dht}." + shared_title)

    total_num_req = @requests.size
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

    # Write the cummulative distribution function for the successful requests
    # over time
    File.open("#{dir_name}/cdf.csv", "w") do |file|
      num_reqs = total_num_req.to_f # I am using the total number, so I can see the failure rate
      # Sorted by latency
      sorted_requests = ok_requests.sort { |a,b| a.lat <=> b.lat }

      current_interval = 0
      max_range = 10 # 10 ms
      accumulated_successes = 0

      file.write "# Time Ratio\n"
      file.write "0 0"

      sorted_requests.each do |request|
        if request.lat > current_interval + max_range
          file.write "#{current_interval} #{accumulated_successes / num_reqs}\n"
          current_interval += max_range
        end
        accumulated_successes += 1
      end

      # Write the same value up until the end of time
      current_value = accumulated_successes / num_reqs
      while current_interval < 5000
        file.write "#{current_interval} #{current_value}\n"
        current_interval += max_range
      end
    end

    temp_gnufile = "output/temp_gnuplot_cdf_#{dir_name.gsub("/", "")}.gp"
    File.open(temp_gnufile, "w") do |gnuplot|
      gnuplot.write "set terminal postscript\n"
      gnuplot.write "set output '#{dir_name}/cdf.eps'\n"
      gnuplot.write "set xtics ('0' 0, '1' 1000, '2' 2000, '3' 3000, '4' 4000, '5' 5000)\n"
      gnuplot.write "set xlabel 'Latency /s'\n"
      gnuplot.write "set xrange [ 0 : 5000 ]\n"
      gnuplot.write "set ylabel 'Probability of having succeeded'\n"
      gnuplot.write "set title \"CDF for #{dht + shared_title}\"\n"
      gnuplot.write "plot '#{dir_name}/cdf.csv' using 1:2 t '' with lines\n"
    end
    `gnuplot #{temp_gnufile}`
    File.delete(temp_gnufile)

    # Calculate the request rate over time
    base_time = @start_metadata[:time]
    binned_requests = bin_requests(@requests, base_time)

    File.open("#{dir_name}/rate_against_time.csv", "w") do |file|
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
    temp_gnufile = "temp_gnuplot_rate_against_time_#{dir_name.gsub("/", "")}.gp"
    File.open(temp_gnufile, "w") do |gnuplot|
      gnuplot.write "set terminal postscript\n"
      gnuplot.write "set output '#{dir_name}/rate_against_time.eps'\n"
      gnuplot.write xtics_min
      gnuplot.write "set xlabel 'Time /min'\n"
      gnuplot.write "set xrange [ 0 : #{normalized_time/1000} ]\n"
      gnuplot.write "set ylabel 'Instantaneous number of request /s'\n"
      gnuplot.write "set title \"Instantaneous number of requests per second over time for #{dht + shared_title}\"\n"
      gnuplot.write "plot '#{dir_name}/rate_against_time.csv' using 1:2 t 'Total rate', \\\n"
      gnuplot.write "     '' using 1:3 t 'Success rate'\n"
    end
    `gnuplot #{temp_gnufile}`
    File.delete(temp_gnufile)
  end

  private
  def bin_requests(reqs, base_time)
    # Bin the requests per second
    bins = {}
    reqs = reqs.to_a.map { |k,v| v }
    good_reqs = reqs.select {|r| r.is_valid_for_start_time?(base_time) }
    good_reqs.each do |request|
      # Bin them by a second
      bin = request.start_time / 1000
      bins[bin] = [] unless bins[bin]
      bins[bin] << request
    end
    bins.to_a.sort.map {|b,r| r}
  end

  def output_metric(ok_requests, metric, metric_name, file_ext, dir_name, graph_title)
    File.open("#{dir_name}/#{file_ext}.csv", "w") do |file|
      file.write "Time #{metric_name}\n"
      
      base_time = @start_metadata[:time]

      ok_requests.each do |request|
        time = request.start_time - base_time
        file.write "#{time} #{request.send(metric)}\n" unless time < 0
      end
    end
    temp_gnufile = "output/temp_gnuplot_#{file_ext}_#{metric}_#{dir_name.gsub("/", "_")}.gp"

    File.open(temp_gnufile, "w") do |gnuplot|
      gnuplot.write "set terminal postscript\n"
      gnuplot.write "set output '#{dir_name}/#{file_ext}.eps'\n"
      gnuplot.write xtics
      gnuplot.write "set xlabel 'Time /min'\n"
      gnuplot.write "set xrange [ 0 : #{normalized_time} ]\n"
      gnuplot.write "set ylabel 'Latency /ms'\n"
      gnuplot.write "set title \"#{graph_title}\"\n"
      gnuplot.write "plot '#{dir_name}/#{file_ext}.csv' using 1:2 t ''\n"
    end
    `gnuplot #{temp_gnufile}`
    File.delete(temp_gnufile)
  end

  # Returns a set of xtic values for the given dataset
  def xtics
    "set xtics (#{(tic_nums.map {|t| "\"#{t[:min]}\" #{t[:position]}" }).join(",")})\n"
  end

  def xtics_min
    "set xtics (#{(tic_nums.map {|t| "\"#{t[:min]}\" #{t[:position] / 1000}" }).join(",")})\n"
  end

  def tic_nums
    msperminute = 60_000
    tic_interval =  normalized_time / 5.0
    num_minutes = (normalized_time / msperminute.to_f).round
    minute_per_tick = num_minutes / 5.0
    tics = []
    0.upto(5) do |position|
      numeric_position = position * tic_interval
      corresponding_minute = ((minute_per_tick * position) * 10).to_i / 10.0
      tics << {:min => corresponding_minute, :position => numeric_position}
    end
    return tics
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

if ARGV.size != 4 then
  puts "Please supply the name of the log file to parse, the name prefix of the output, rate and dht name"
  exit 1
end

filename = ARGV.first
logParser = LogParser.new(filename)
logParser.parse
if ARGV.size == 4 then
  outputFilename = ARGV[1]
  rate = ARGV[2]
  dht = ARGV[3]
  logParser.to_file(outputFilename, rate, dht)
else
  logParser.output
end
