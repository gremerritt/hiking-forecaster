require 'json'

creds = {
         "google" => {"api_key" => "",
                      "calls_per_minute" => "",
                      "calls_per_day" => ""},
         "weather" => {
                      "api_key" => "",
                      "calls_per_minute" => "",
                      "calls_per_day" => ""}
        }
		
File.open(".credentials.json", "w") { |f| f.write(creds.to_json) }