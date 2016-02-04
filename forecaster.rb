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
  @@weather_fields = ['postal_code',
              'timestamp',
              'tempMax',
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
    #puts "weather_total_calls: #{@@weather_total_calls}\nweather_last_call: #{@@weather_last_call}\ngoogle_total_calls: #{@@google_total_calls}\ngoogle_last_call: #{@@google_last_call}"
  end
  
  def weather_call(postal_code_eq, timestamp_eq)
    begin
      raise "Daily Call Limit Reached to Weather API - #{postal_code_eq},#{timestamp_eq}" if @@weather_total_calls > @@weather_call_limit
      time_allowed = @@weather_last_call + (60/@@weather_calls_per_minute)
      time_now = Time.now.to_i
      sleep(time_allowed - time_now) if time_allowed > time_now
      
      uri = URI(@@weather_uri)
      params = { :postal_code_eq => postal_code_eq,
                 :timestamp_eq => timestamp_eq,
                 :country_eq => 'US',
                 :fields => @@weather_fields.join(',')
               }
      uri.query = URI.encode_www_form(params)
      res = Net::HTTP.get_response(uri)
      json_response = JSON.parse(res.body)
      if res.is_a?(Net::HTTPSuccess)
        pprint = JSON.pretty_generate(json_response)
        puts pprint
      else
        puts json_response['message']
      end
      @@weather_last_call = Time.now.to_i
      @@weather_total_calls += 1
      return true
    rescue StandardError => err
      puts err
      return false
    end
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
          puts json_response['message']
        end
      end
    rescue StandardError => err
      puts err
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
#   start_date = getDate("Enter a start date (YYYY-MM-DD): ")
#   end_date = getDate("Enter an end date (YYYY-MM-DD): ")
  start_date = Date.parse("2017-04-01")
  end_date = Date.parse("2017-07-07")
  num_days = (end_date - start_date).to_i + 1
  puts "Total number of days:   #{num_days}"
  
  begin
    print 'Parsing KML file... '
    data = parseKML('pct.kml')
    return if !data
    puts 'Success!'
    puts "Total number of points: #{data.length}"
    
    if data.length > num_days
      div = (data.length / num_days).to_i
      mod = data.length % num_days
      add = (num_days.to_f / mod).ceil
      puts "div: #{div}"
      puts "mod: #{mod}"
      puts "add: #{add}"
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
    end

    number_to_run = 15
    
    print 'Translating lat/lon data to city/state/zipcode and getting weather data... 0%'
    #data = [['city', 'state', 'zip', 'lat', 'lon', 'day', 'date']]
    percent_done = 0
    File.open('pct_zipcodes.csv', 'w') do |f|
      data.each_with_index do |d, index|
        rslt = api.google_call(d[1], d[0])
        d.push(*rslt)
        if ((index.to_f / data.length)*100).to_i > percent_done
          percent_done = ((index.to_f / data.length)*100).to_i
          print "\rTranslating lat/lon data to city, state, and zipcode... #{percent_done}%"
        end
        break if index == number_to_run - 1
      end
    end
    puts "\rTranslating lat/lon data to city, state, and zipcode... Success!"
    
    data.each { |d| puts d.to_s }
    File.open("pct_data.csv", "w") {|f| f.write(data.inject([]) { |csv, row|  csv << CSV.generate_line(row) }.join(""))}
    
  ensure
    api.flush
  end
end

main