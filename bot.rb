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
  parser = MyPostgresParser.new
  channel_id = event.message.channel.id
  title = event.message.content
  visibility = ""
  output_channel_id = 0
  playlist = ""
  yukkuri = false
  @channel_data.each do |channel_data|
    if channel_data["channel_id"] == channel_id
      visibility = channel_data["visibility"]
      output_channel_id = channel_data["output_channel_id"]
      playlist = channel_data["playlist"]
      yukkuri = channel_data["yukkuri"]
      break
    end
  end
  replay_file_binary = URI.open(file.url).read
  data = {
      "replay_name" => file.filename,
      "replay_file_binary" => Base64.encode64(replay_file_binary),
      "upload_to" => "youtube",
      "visibility" => visibility,
      "title" => title,
      "playlist" => playlist,
      "yukkuri" => yukkuri,
      "token" => "aaaa"
  }
  client = HTTPClient.new
  response = client.post("https://databaseapi7171.herokuapp.com/api/replay_data", JSON.generate(data))
  print(JSON.parse(response.content))
  @conn.exec("
    INSERT INTO in_watch_replays (replay_name, unix_time, visibility, title, output_channel_id, playlist, yukkuri)
    VALUES ('#{file.filename}', #{Time.now.to_i}, '#{visibility}', '#{title}',#{output_channel_id}, '#{playlist}', #{yukkuri})
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
    if data["yukkuri"] == "f"
      channel_data[i]["yukkuri"] = false
    else
      channel_data[i]["yukkuri"] = true
    end
  end
  @channel_data = channel_data
  result = @conn.exec("SELECT * FROM admin_users")
  admin_user_data = result.to_a
  admin_user_data.each_with_index do |data, i|
    admin_user_data[i]["authorized_servers"] = parser.parse_pg_array(data["authorized_servers"])
    admin_user_data[i]["authorized_servers"].map!(&:to_i)
  end
  @admin_user_data = admin_user_data
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
  @admin_user_data.each do |admin_user_data|
    if admin_user_data["user_id"] == user_id || admin_user_data["authorized_servers"].include?(server_id)
      print("authorized")
      return true
    end
  end
  print("not authorized")
  return false
end

def CheckConvertionStatus()
  in_watch_replays = @conn.exec("SELECT * FROM in_watch_replays").to_a
  client = HTTPClient.new()
  body = {"conversion_status" => "completed", "option" => "all"}
  response = client.get("https://databaseapi7171.herokuapp.com/api/replay_data/filter_by", body)
  completed_replay_data = JSON.parse(response.content)
  in_watch_replays.each do |in_watch_replay|
    completed_replay_data["data"].each do |_replay_data|
      if _replay_data["replay_name"] == in_watch_replay["replay_name"] && _replay_data["conversion_status"] == "completed"
        _replay_data["output_channel_id"] = in_watch_replay["output_channel_id"]
        return _replay_data
      end
    end
  end
  return false
end

def Notify(replay_data, bot)
  if replay_data["visibility"] == "public"
    bot.send_message(replay_data["output_channel_id"],"公開設定です\n@here\nhttps://youtu.be/#{replay_data["video_id"]}")
  else
    bot.send_message(replay_data["output_channel_id"],"限定公開設定です\nhttps://youtu.be/#{replay_data["video_id"]}")
  end
end

def UpdateInWatchReplays(replay_data)
  @conn.exec("DELETE FROM in_watch_replays WHERE replay_name='#{replay_data["replay_name"]}'")
end

def UpdateBotGame(bot)
  client = HTTPClient.new()
  body = {"conversion_status" => "in queue"}
  response = client.get("https://databaseapi7171.herokuapp.com/api/replay_data/filter_by", body)
  in_queue_replay_data = JSON.parse(response.content)
  body = {"conversion_status" => "in process"}
  response = client.get("https://databaseapi7171.herokuapp.com/api/replay_data/filter_by", body)
  in_process_replay_data = JSON.parse(response.content)
  if in_process_replay_data["meta"]["count"] == 0
    processing = "Nothing"
  else
    processing = in_process_replay_data["data"][0]["replay_name"]
  end
  game = "#{in_queue_replay_data["meta"]["count"]} replays in queue / processing #{processing}"
  bot.game = game
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
  ResetChannelConst()
  result = CheckConvertionStatus()
  if result != false
    p result
    Notify(result, bot)
    UpdateInWatchReplays(result)
  end
  UpdateBotGame(bot)
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

bot.reaction_add() do |event|
  if not Authorised(event)
    break
  end
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
    SET yukkuri=True
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
