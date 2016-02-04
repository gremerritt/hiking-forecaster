require 'net/http'
require 'json'
require 'csv'
require 'nokogiri'
require 'date'

class WeatherAPI
  @@weather_root = 'https://api.weathersource.com/v1/'
  @@weather_key = 'b2f3ea7109d2f376bd0a'
  @@weather_resource = 'history_by_postal_code'
  @@weather_format = 'json'
  @@weather_fields = ['tempMax',
                      'tempAvg',
                      'tempMin',
                      'precip',
                      'snowfall',
                      'windSpdMax',
                      'windSpdAvg',
                      'windSpdMin',
                      'feelsLikeMax',
                      'feelsLikeAvg',
                      'feelsLikeMin']
  @@weather_total_calls
  @@weather_last_call
  @@weather_calls_per_minute = 10
  @@weather_call_limit = 1000
  
  @@google_key = 'AIzaSyCAUWj528-GBPah2yCIYfKR_7ThOvEm8MU'
  @@google_root = 'https://maps.googleapis.com/maps/api/geocode/json'
  @@google_total_calls
  @@google_last_call
  @@google_calls_per_minute = 10
  @@google_call_limit = 2500
  
  def initialize
    @@weather_uri = "#{@@weather_root}#{@@weather_key}/#{@@weather_resource}.#{@@weather_format}"
    t = Time.new
    @@today = "#{t.year}-#{t.month}-#{t.day}"
    read_call_counts
    setup_coord_cache
    setup_weather_cache
    #puts "weather_total_calls: #{@@weather_total_calls}\nweather_last_call: #{@@weather_last_call}\ngoogle_total_calls: #{@@google_total_calls}\ngoogle_last_call: #{@@google_last_call}"
  end
  
  def weather_call(postal_code_eq, timestamp_eq)
    begin
      return_val = Array.new
      @@weather_fields.length.times { return_val.push("") }
      return return_val if postal_code_eq == ""
      
      timestamp = getRelativeDate(timestamp_eq, 2)
      key = "#{postal_code_eq}|#{timestamp}"
      
      if !@@weather_cache[key].nil?
        return_val[0] = @@weather_cache[key]["feelsLikeMin"]
        return_val[1] = @@weather_cache[key]["feelsLikeAvg"]
        return_val[2] = @@weather_cache[key]["feelsLikeMax"]
        return_val[3] = @@weather_cache[key]["precip"]
        return_val[4] = @@weather_cache[key]["snowfall"]
        return_val[5] = @@weather_cache[key]["tempMin"]
        return_val[6] = @@weather_cache[key]["tempAvg"]
        return_val[7] = @@weather_cache[key]["tempMax"]
        return_val[8] = @@weather_cache[key]["windSpdMin"]
        return_val[9] = @@weather_cache[key]["windSpdAvg"]
        return_val[10] = @@weather_cache[key]["windSpdMax"]
      else
        raise "Daily Call Limit Reached to Weather API - #{postal_code_eq},#{timestamp_eq}" if @@weather_total_calls > @@weather_call_limit
        time_allowed = @@weather_last_call + (60/@@weather_calls_per_minute)
        time_now = Time.now.to_i
        sleep(time_allowed - time_now) if time_allowed > time_now
        
        uri = URI(@@weather_uri)
        params = {:period => 'day',
                  :postal_code_eq => postal_code_eq,
                  :country_eq => 'US',
                  :timestamp_eq => timestamp,
                  :fields => @@weather_fields.join(',')}
        uri.query = URI.encode_www_form(params)
        res = Net::HTTP.get_response(uri)
        json_response = JSON.parse(res.body)
        @@weather_last_call = Time.now.to_i
        @@weather_total_calls += 1
        if res.is_a?(Net::HTTPSuccess)
          json_response[0].each do |key, val|
            case key
            when "feelsLikeMin"
              return_val[0] = val
            when "feelsLikeAvg"
              return_val[1] = val
            when "feelsLikeMax"
              return_val[2] = val
            when "precip"
              return_val[3] = val
            when "snowfall"
              return_val[4] = val
            when "tempMin"
              return_val[5] = val
            when "tempAvg"
              return_val[6] = val
            when "tempMax"
              return_val[7] = val
            when "windSpdMin"
              return_val[8] = val
            when "windSpdAvg"
              return_val[9] = val
            when "windSpdMax"
              return_val[10] = val
            end
          end
          
          @@weather_cache[key] = {"feelsLikeMin" => return_val[0],
                                  "feelsLikeAvg" => return_val[1],
                                  "feelsLikeMax" => return_val[2],
                                  "precip" => return_val[3],
                                  "snowfall" => return_val[4],
                                  "tempMin" => return_val[5],
                                  "tempAvg" => return_val[6],
                                  "tempMax" => return_val[7],
                                  "windSpdMin" => return_val[8],
                                  "windSpdAvg" => return_val[9],
                                  "windSpdMax" => return_val[10]}
        else
          #puts json_response['message']
        end
      end
    rescue StandardError => err
      #puts err
    end
    return return_val
  end
  
  def getRelativeDate(timestamp_eq, difference)
    date = timestamp_eq.split("-")
    year = date[0].to_i
    year -= difference
    date[0] = year.to_s
    return date.join("-")
  end
  
  def google_call(lat, lon, debug = false)	
    begin
      return_val = ['', '', '']
      key = "#{'%.3f' % lat.to_f},#{'%.3f' % lon.to_f}"
      if !@@coord_cache[key].nil?
        return_val[0] = @@coord_cache[key]["city"]
        return_val[1] = @@coord_cache[key]["state"]
        return_val[2] = @@coord_cache[key]["zipcode"]
      else
        raise "Daily Call Limit Reached for Google API - #{lat},#{lon}" if @@google_total_calls > @@google_call_limit
        time_allowed = @@google_last_call + (60/@@google_calls_per_minute)
        time_now = Time.now.to_i
        sleep(time_allowed - time_now) if time_allowed > time_now
        
        uri = URI(@@google_root)
        params = { :latlng => "#{lat},#{lon}",
                   :key => @@google_key
                 }
        uri.query = URI.encode_www_form(params)
        res = Net::HTTP.get_response(uri)
        json_response = JSON.parse(res.body)
        @@google_last_call = Time.now.to_i
        @@google_total_calls += 1
        if res.is_a?(Net::HTTPSuccess)
          puts "#{JSON.pretty_generate(json_response)}\n\n" if debug
          if json_response['status'] == 'OK'
            puts "OK\n\n" if debug
            address = json_response['results'][0]
            puts "#{JSON.pretty_generate(address)}\n\n" if debug
            address['address_components'].each do |address_component|
              puts "#{address_component}\n\n" if debug
              
              # city
              if address_component['types'][0] == 'locality'
                puts "#{address_component['long_name']}\n\n" if debug
                return_val[0] = address_component['long_name']
              end
              
              #state
              if address_component['types'][0] == 'administrative_area_level_1'
                puts "#{address_component['short_name']}\n\n" if debug
                return_val[1] = address_component['short_name']
              end
              
              #zip
              if address_component['types'][0] == 'postal_code'
                puts "#{address_component['long_name'].to_s}\n\n" if debug
                return_val[2] = address_component['long_name'].to_s
              end
              
              @@coord_cache[key] = {"city" => return_val[0],
                                    "state" => return_val[1],
                                    "zipcode" => return_val[2]}
            end
          else
            puts "No address info found for #{lat},#{lon}"
          end
        else
          #puts json_response['message']
        end
      end
    rescue StandardError => err
      #puts err
    end
    return return_val
  end
  
  def setup_coord_cache
    File.open(".coordinate_cache.json", "a+") do |f|
      contents = f.read
      if contents != ""
        @@coord_cache = JSON.parse(contents)
      else
        @@coord_cache = {}
      end
    end
  end
  
  def setup_weather_cache
    File.open(".weather_cache.json", "a+") do |f|
      contents = f.read
      if contents != ""
        @@weather_cache = JSON.parse(contents)
      else
        @@weather_cache = {}
      end
    end
  end
  
  def read_call_counts
    fname = '.forecaster_calls.json'
    update = false
    File.open(fname, "a+") do |f|
      contents = f.read
      if contents == ""
        @@weather_last_call = 0
        @@weather_total_calls = 0
        @@google_last_call = 0
        @@google_total_calls = 0
        f.write({"weather" => {'last_call' => @@weather_last_call, @@today => @@weather_total_calls},
                 "google" => {'last_call' => @@google_last_call, @@today => @@google_total_calls}}.to_json)
      else
        data = JSON.parse(contents)
        
        @@weather_last_call = data['weather']['last_call']
        if data['weather'][@@today].nil?
          @@weather_total_calls = 0
          data['weather'][@@today] = 0
          update = true
        else
          @@weather_total_calls = data['weather'][@@today]
        end
        
        @@google_last_call = data['google']['last_call']
        if data['google'][@@today].nil?
          @@google_total_calls = 0
          data['google'][@@today] = 0
          update = true
        else
          @@google_total_calls = data['google'][@@today]
        end
        
        if update
          f.truncate(0)
          f.write(data.to_json)
        end
      end
    end
  end
  
  def flush
    File.open(".forecaster_calls.json", "w") do |f|
      f.write({"weather" => {'last_call' => @@weather_last_call, @@today => @@weather_total_calls},
               "google" => {'last_call' => @@google_last_call, @@today => @@google_total_calls}}.to_json)
    end
    
    File.open(".coordinate_cache.json", "w") do |f|
      f.write(@@coord_cache.to_json)
    end
    
    File.open(".weather_cache.json", "w") do |f|
      f.write(@@weather_cache.to_json)
    end
  end
end

def parseKML(filepath)
  result = Array.new
  begin
    kml = File.read(filepath)
  rescue
    puts "Can't read #{filepath}"
    return false
  end
  
  begin
    doc = Nokogiri::XML(kml)
    doc.search('coordinates').each do |coord|
      result.push(coord.content.split(',').slice(0, 2))
    end
  rescue Exception => msg
    puts msg
    puts "Error parsing #{filepath}"
    return false
  end
  return result
end

def getDate(prompt)
  valid_date = false
  while !valid_date
    begin
      print prompt
      date = Date.parse(STDIN.gets.chomp)
      return date
    rescue StandardError => msg
      puts " => Invalid Date Format"
    end
  end
end

def main
  api = WeatherAPI.new
  print "What trail is this for? "
  trail = STDIN.gets.chomp
  print "Enter the path to your KML file: "
  kml_file = STDIN.gets.chomp
  print 'Parsing KML file... '
  data = parseKML(File.expand_path(kml_file))
  return if !data
  puts 'Success!'
  puts "Total number of points: #{data.length}"
  
  start_date = getDate("Enter a start date (YYYY-MM-DD): ")
  end_date = getDate("Enter an end date (YYYY-MM-DD): ")
  num_days = (end_date - start_date).to_i + 1
  puts "Total number of days:   #{num_days}"
  
  begin
    if data.length > num_days
      div = (data.length / num_days).to_i
      mod = data.length % num_days
      add = (num_days.to_f / mod).ceil
      counts = Array.new(num_days, div)
      rand = Random.new
      mod.times do
        while true
          index = rand.rand(num_days)
          if counts[index] != div + 1
            counts[index] += 1
            break
          end
        end
      end
      
      loc_index = 0
      tmp_date = start_date
      counts.each_with_index do |count, day|
        count.times do
          data[loc_index].push(day+1)
          data[loc_index].push(tmp_date.strftime())
          loc_index += 1
        end
        tmp_date += 1
      end
    else
      "Having the number of hiking days be less than the number of coordinates from your KML file is not yet supported."
      return
    end
    
    print 'Translating lat/lon data to city/state/zipcode and getting weather data... 0%'
    percent_done = 0
    data.each_with_index do |d, index|
      # get city/state/zip info
      rslt = api.google_call(d[1], d[0])
      d.push(*rslt)
      
      # get weather data
      rslt = api.weather_call(d[6], d[3])
      d.push(*rslt)
      
      if ((index.to_f / data.length)*100).to_i > percent_done
        percent_done = ((index.to_f / data.length)*100).to_i
        print "\rTranslating lat/lon data to city/state/zipcode and getting weather data... #{percent_done}%"
      end
    end
    puts "\rTranslating lat/lon data to city/state/zipcode and getting weather data... Success!"
    
    header = ["lat",
              "lon",
              "day",
              "date",
              "city",
              "state",
              "zipcode",
              "feelsLikeMin",
              "feelsLikeAvg",
              "feelsLikeMax",
              "precip",
              "snowfall",
              "tempMin",
              "tempAvg",
              "tempMax",
              "windSpdMin",
              "windSpdAvg",
              "windSpdMax"]
    data.insert(0, header)
    File.open("#{trail}_data.csv", "w") {|f| f.write(data.inject([]) { |csv, row|  csv << CSV.generate_line(row) }.join(""))}
  ensure
    api.flush
  end
end

main