require "httpclient"
require "open-uri"
require "json"
require "date"
require "base64"

file_url = "https://cdn.discordapp.com/attachments/830306246976471060/865627354066976778/20210717_0057__penguin_7171_IS-7_2307188353511042151.wotbreplay"
replay_file_binary = URI.open(file_url).read

data = {
    "replay_name" => "20210717_0057__penguin_7171_IS-7_2307188353511042151.wotbreplay",
    "replay_file_binary" => Base64.encode64(replay_file_binary),
    "upload_to" => "youtube",
    "visibility" => "unlisted",
    "title" => "ahoge",
    "playlist" => "WWN",
    "yukkuri" => True,
    "token" => "aaaa"
}

client = HTTPClient.new
client.post("http://127.0.0.1:5000/api/replay_data", JSON.generate(data))
