require 'discordrb'
require 'open-uri'
require 'json'
require 'date'
require 'base64'
require 'httpclient'
require 'pg'
require 'pg_array_parser'

class MyPostgresParser
  include PgArrayParser
end

def UpdateReplayData(file,event)
  channel_id = event.message.channel.id
  title = event.message.content
  visibility = ""
  output_channel_id = 0
  playlist = ""
  @channel_data.each do |channel_data|
    if channel_data["channel_id"] == channel_id
      visibility = channel_data["visibility"]
      output_channel_id = channel_data["output_channel_id"]
      playlist = channel_data["playlist"]
      options = parser.parse_pg_array(channel_data["options"])
      p options
      break
    end
  end
  replay_file_binary = URI.open(file.url).read
  data = {
      "replay_name" => file.filename,
      "replay_file_binary" => Base64.encode64(replay_file_binary),
      "user_id" => 0,
      "user_type" => "discord",
      "upload_to" => "youtube",
      "visibility" => visibility,
      "title" => title,
      "playlist" => playlist,
      "options" => options,
      "token" => "aaaa"
  }
  client = HTTPClient.new
  client.post("https://replayrecieverapi.herokuapp.com/api/replay_data", JSON.generate(data))
  @conn.exec("
    INSERT INTO in_watch_replays (filename, time_unix, channel_id, visibility, title, output_channel_id, playlist, options)
    VALUES ('#{file.filename}', #{Time.now.to_i}, #{channel_id},'#{visibility}','#{title}',#{output_channel_id},'#{playlist}', ARRAY#{options})
  ")
end

def ResetChannelConst()
  parser = MyPostgresParser.new
  result = @conn.exec("SELECT * FROM channel_data")
  channel_data = result.to_a
  channel_data.each_with_index do |data, i|
    channel_data[i]["channel_id"] = data["channel_id"].to_i
    channel_data[i]["server_id"] = data["server_id"].to_i
    channel_data[i]["output_channel_id"] = data["output_channel_id"].to_i
  end
  @channel_data = channel_data
  result = @conn.exec("SELECT * FROM admin_users")
  admin_user_data = result.to_a
  admin_user_data.each_with_index do |data, i|
    admin_user_data[i]["authorized_servers"] = parser.parse_pg_array(data["authorized_servers"])
    admin_user_data[i]["authorized_servers"].map!(&:to_i)
  end
  @admin_user_data = admin_user_data
  p "constant set"
end

def DBConnect()
  database_url = ENV["DATABASE_URL"]
  uri = URI.parse(database_url)
  conn = PG::connect(
    host: uri.hostname,
    dbname: uri.path[1..-1],
    user: uri.user,
    port: uri.port,
    password: uri.password
  )
  return conn
end

def Authorised(event)
  user_id = event.message.user.id
  server_id = event.message.channel.server.id
  result = false
  @admin_user_data.each do |admin_user_data|
    if admin_user_data["user_id"] == user_id || admin_user_data["authorized_servers"].include?(server_id)
      result = true
    end
  end
  return result
end

def CheckConvertionStatus()
  in_watch_replays = @conn.exec("SELECT * FROM in_watch_replays").to_a
  client = HTTPClient.new()
  replay_data = JSON.parse(client.get("https://replayrecieverapi.herokuapp.com/api/replay_data").content)
  in_watch_replays.each do |in_watch_replay|
    replay_data.each do |_replay_data|
      if _replay_data["replay_name"] == in_watch_replay["replay_name"] || _replay_data["conversion_status"] == "completed"
        _replay_data["output_channel_id"] = in_watch_replay["output_channel_id"]
        return _replay_data
      end
    end
  end
  return false
end

def Notify(replay_data)
  if replay_data["visibility"] == "public"
    @bot.send_message(replay_data["output_channel_id"],"公開設定です\n@here\n#{replay_data["youtube_url"]}")
  else
    @bot.send_message(replay_data["output_channel_id"],"限定公開設定です\n#{replay_data["youtube_url"]}")
  end
end

def UpdateInWatchReplays(replay_data)
  @conn.exec("DELETE FROM in_watch_replay WHERE replay_name='#{replay_data["replay_name"]}'")
end

bot = Discordrb::Commands::CommandBot.new(
  token: ENV['TOKEN'],
  client_id: ENV['CLIENT_ID'],
  prefix: '!'
)
@conn = DBConnect()

bot.ready do
  p "ready"
  ResetChannelConst()
end

bot.heartbeat do
  result = CheckConvertionStatus()
  if result != false
    Notify(result)
    UpdateInWatchReplays(result)
  end
end

bot.message() do |event|
  from_set_channel = false
  @channel_data.each do |channel_data|
    if channel_data["channel_id"] == event.message.channel.id
      from_set_channel = true
    end
  end
  if from_set_channel
    p "message in #{event.server.name} / #{event.channel.name}"
    if not event.message.attachments.empty?
      p event.message.content
      file = event.message.attachments[0]
      if File.extname(file.filename) == ".wotbreplay"
        channel_id = event.message.channel.id
        UpdateReplayData(file,event)
        event.message.create_reaction("☑️")
      end
    end
  end
end

bot.command :morph_set_input do |event|
  channel_id = event.message.channel.id.to_s
  channel_name = event.message.channel.name.to_s
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  @conn.exec("
    INSERT INTO channel_data (channel_id, channel_name, server_id, server_name, output_channel_id, visibility, playlist)
    VALUES (#{channel_id},'#{channel_name}',#{bot.channel(channel_id).server.id},'#{bot.channel(channel_id).server.name}',#{channel_id},'unlisted','false')
  ")
  bot.send_message(channel_id,"このチャンネルに送信されたリプレイを変換し、URLを返信します。\nURLの送信先を変更したい場合は任意のチャンネルで!morph_set_outputと送信してください。\n動画を公開設定にしたい場合はURLが送信されるチャンネルで!morph_set_publicと送信してください。")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_output do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  output_channel_id = event.message.channel.id
  event.server.channels.each do |channel|
    @conn.exec("
      UPDATE channel_data
      SET output_channel_id=#{output_channel_id}
      WHERE channel_id=#{channel.id}
    ")
  end
  channel_name_list = @conn.exec("
    SELECT channel_name
    FROM channel_data
    WHERE server_id=#{event.server.id}
  ").to_a
  channel_names = ""
  channel_name_list.each do |channel_name|
    channel_names = channel_names + "\n" + channel_name["channel_name"]
  end
  bot.send_message(output_channel_id,"以下のチャンネルのURL送信先をここに変更します。#{channel_names}")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_public do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  channel_id = event.message.channel.id
  @conn.exec("
    UPDATE channel_data
    SET visibility='public'
    WHERE channel_id=#{channel_id}
  ")
  bot.send_message(channel_id,"このチャンネルに送信されたリプレイは公開設定でアップロードされます。")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_yukkuri do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  channel_id = event.message.channel.id.to_s
  @conn.exec("
    UPDATE channel_data
    SET options=ARRAY['yukkuri']
    WHERE channel_id=#{channel_id}
  ")
  bot.send_message(channel_id,"このチャンネルに送信されたリプレイはゆっくり音声と共にでアップロードされます。")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_playlist do |event|
  bot.send_message(channel_id,"This command is back in development.\nSorry for inconvenience.")
  break
  # if not Authorised(event)
  #   bot.send_message(channel_id,"You are not authorized\nContact the developer")
  #   break
  # end
  # channel_id = event.message.channel.id.to_s
  # message = event.message.content
  # message.slice!(0, 20)
  # playlist_name = message
  # playlist_data = plhandler.FindPlayList(
  #   cookie_file_path: "repcon1.json",
  #   playlist_name: playlist_name
  # )
  # if playlist_data.empty?
  #   bot.send_message(channel_id,"プレイリストを作成します。しばらくお待ちください。")
  #   playlist_data = plhandler.MakePlaylist(
  #     cookie_file_path: "repcon1.json",
  #     playlist_name: playlist_name
  #   )
  # end
  # bot.send_message(channel_id,"このチャンネルの動画は以下のプレイリストに登録されます。\n#{playlist_data["url"]}")
  # channel_data = File.open("channel_data.json") do |file|
  #   JSON.load(file)
  # end
  # channel_data[channel_id]["playlist"] = playlist_name
  # open("channel_data.json", 'w') do |file|
  #   pretty_channel_data = JSON.pretty_generate(channel_data)
  #   file.write(pretty_channel_data)
  # end
  # ResetChannelConst()
  # a = ""
end

bot.command :morph_set_unlisted_playlist do |event|
  bot.send_message(channel_id,"This command is back in development.\nSorry for inconvenience.")
  break
  # if not Authorised(event)
  #   bot.send_message(channel_id,"You are not authorized\nContact the developer")
  #   break
  # end
  # channel_id = event.message.channel.id.to_s
  # message = event.message.content
  # message.slice!(0, 29)
  # playlist_name = message
  # playlist_data = plhandler.FindPlayList(
  #   cookie_file_path: "repcon1.json",
  #   playlist_name: playlist_name
  # )
  # if playlist_data.empty? || playlist_data["visibility"] != "unlisted"
  #   bot.send_message(channel_id,"プレイリストを作成します。しばらくお待ちください。")
  #   playlist_data = plhandler.MakePlaylist(
  #     cookie_file_path: "repcon1.json",
  #     playlist_name: playlist_name,
  #     playlist_visibility: "unlisted"
  #   )
  # end
  # bot.send_message(channel_id,"このチャンネルの動画は以下のプレイリストに登録されます。\n#{playlist_data["url"]}")
  # channel_data = File.open("channel_data.json") do |file|
  #   JSON.load(file)
  # end
  # channel_data[channel_id]["playlist"] = playlist_name
  # open("channel_data.json", 'w') do |file|
  #   pretty_channel_data = JSON.pretty_generate(channel_data)
  #   file.write(pretty_channel_data)
  # end
  # ResetChannelConst()
  # a = ""
end

bot.command :morph_reset do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  channel_id = event.message.channel.id
  event.server.channels.each do |channel|
    @conn.exec("
      DELETE FROM channel_data
      WHERE channel_id=#{channel.id}
    ")
  end
  bot.send_message(channel_id,"このサーバーでの設定がリセットされました。\n利用を再開するには任意のチャンネルで!morph_set_inputを送信してください")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_admin do |event|
  channel_id = event.message.channel.id
  user_id = event.message.user.id
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
  else
    new_admin_user_id = event.message.content
    new_admin_user_id.slice!(0, 17)
    new_admin_user_name = bot.user(new_admin_user_id).name
    server_id = event.message.channel.server.id
    server_name = event.message.channel.server.name
    result = @conn.exec("SELECT * FROM admin_users WHERE user_id=#{new_admin_user_id}")
    if result.to_a.empty?
      @conn.exec("
        INSERT INTO admin_users (user_id, name, authorized_servers)
        VALUES (#{new_admin_user_id}, '#{new_admin_user_name}', ARRAY[#{server_id}])
        ")
    else
      @conn.exec("
        UPDATE admin_users
        SET authorized_servers=authorized_servers||#{server_id}
        WHERE user_id=#{new_admin_user_id}
        ")
    end
    bot.send_message(channel_id,"Assigned #{new_admin_user_name} as an administrator of #{server_name}")
  end
end

bot.command :morph_help do |event|
  channel_id = event.message.channel.id
  bot.send_message(channel_id,"「コマンド一覧」\n!morph_set_input : \nリプレイが投稿されるチャンネルを指定\n!morph_set_output : \n動画送信先を指定する。\n!morph_set_public : \n公開設定を限定公開から公開に変更する。\n!morph_set_playlist : \nチャンネルの動画を公開プレイリストに登録する。\n（例）!morph_set_playlist 至高の戦闘\n!morph_set_unlisted_playlist : \nチャンネルの動画を限定公開プレイリストに登録する。\n!morph_reset : \nサーバーにおけるボットの設定を初期化する。")
end

bot.command :test do |event|
end

bot.run
