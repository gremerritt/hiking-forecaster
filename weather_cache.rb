require 'json'

weather_cache = Hash.new
File.open(".weather_cache.json", "a+") do |f|
  contents = f.read
  weather_cache = JSON.parse(contents)
end

#puts weather_cache

new_cache = Hash.new
weather_cache.each do |key, value|
  old_key = key.split("|")
  if new_cache[old_key[0]].nil?
    new_cache[old_key[0]] = {old_key[1] => value}
  else
    new_cache[old_key[0]][old_key[1]] = value
  end
end

File.open(".weather_cache_new.json", "w") do |f|
  f.write(new_cache.to_json)
end