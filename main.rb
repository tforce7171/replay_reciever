require 'discordrb'
require 'open-uri'
require 'json'
require 'yaml'
require 'dotenv'
require 'date'
require_relative 'youtube_uploader'

Dotenv.load('secret.env')
bot = Discordrb::Commands::CommandBot.new(
  token: ENV['TOKEN'],
  client_id: ENV['CLIENT_ID'],
  prefix: '!'
)
plhandler = YoutubePlaylistHandler.new()

def UpdateReplayData(file,event)
  channel_id = event.message.channel.id.to_s
  title = event.message.content
  replay_data = File.open("replay_data.json") do |file|
    JSON.load(file)
  end
  data = {
    "time_unix" => Time.now.to_i,
    "file_url" => file.url,
    "channel_id" => channel_id,
    "visibility" => @channel_data[channel_id]["visibility"],
    "title" => title,
    "output_channel_id" => @channel_data[channel_id]["output_channel_id"],
    "playlist" => @channel_data[channel_id]["playlist"]
  }
  replay_data[file.filename] = data
  p replay_data
  open("replay_data.json", 'w') do |file|
    pretty_replay_data = JSON.pretty_generate(replay_data)
    file.write(pretty_replay_data)
  end
end

def ResetChannelConst()
  @channel_data = File.open("channel_data.json") do |file|
    JSON.load(file)
  end
  @admin_user_data = File.open("admin_users.json") do |file|
    JSON.load(file)
  end
end

def Authorised(event)
  user_id = event.message.user.id.to_s
  server_id = event.message.channel.server.id.to_s
  if not @admin_user_data.has_key?(user_id)
    return false
  elsif not @admin_user_data[user_id]["authorized_servers"].include?(server_id) || @admin_user_data[user_id]["authorized_servers"] == "all"
    return false
  else
    return true
  end
end

bot.ready do
  p "ready"
  ResetChannelConst()
end

bot.heartbeat do
end

bot.message() do |event|
  if @channel_data.has_key?(event.message.channel.id.to_s)
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
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  channel_data = File.open("channel_data.json") do |file|
    JSON.load(file)
  end
  channel_data[channel_id] = {
    "channel_name": bot.channel(channel_id).name,
    "server_name": bot.channel(channel_id).server.name,
    "output_channel_id": channel_id,
    "visibility": "unlisted",
    "playlist": false,
    "server_id": bot.channel(channel_id).server.id
  }
  open("channel_data.json", 'w') do |file|
    pretty_channel_data = JSON.pretty_generate(channel_data)
    file.write(pretty_channel_data)
  end
  bot.send_message(channel_id,"このチャンネルに送信されたリプレイを変換し、URLを返信します。\nURLの送信先を変更したい場合は任意のチャンネルで!morph_set_outputと送信してください。\n動画を公開設定にしたい場合はURLが送信されるチャンネルで!morph_set_publicと送信してください。")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_output do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  output_channel_id = event.message.channel.id.to_s
  channel_names = ""
  event.server.channels.each do |channel|
    channel_data = File.open("channel_data.json") do |file|
      JSON.load(file)
    end
    if @channel_data.has_key?(channel.id.to_s)
      channel_data[channel.id.to_s]["output_channel_id"] = output_channel_id
      channel_names = channel_names + "\n#{channel.name}"
    end
    open("channel_data.json", 'w') do |file|
      pretty_channel_data = JSON.pretty_generate(channel_data)
      file.write(pretty_channel_data)
    end
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
  channel_id = event.message.channel.id.to_s
  channel_data = File.open("channel_data.json") do |file|
    JSON.load(file)
  end
  channel_data[channel_id]["visibility"] = "public"
  open("channel_data.json", 'w') do |file|
    pretty_channel_data = JSON.pretty_generate(channel_data)
    file.write(pretty_channel_data)
  end
  bot.send_message(channel_id,"このチャンネルに送信されたリプレイは公開設定でアップロードされます。")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_playlist do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  channel_id = event.message.channel.id.to_s
  message = event.message.content
  message.slice!(0, 20)
  playlist_name = message
  playlist_data = plhandler.FindPlayList(
    cookie_file_path: "repcon1.json",
    playlist_name: playlist_name
  )
  if playlist_data.empty?
    bot.send_message(channel_id,"プレイリストを作成します。しばらくお待ちください。")
    playlist_data = plhandler.MakePlaylist(
      cookie_file_path: "repcon1.json",
      playlist_name: playlist_name
    )
  end
  bot.send_message(channel_id,"このチャンネルの動画は以下のプレイリストに登録されます。\n#{playlist_data["url"]}")
  channel_data = File.open("channel_data.json") do |file|
    JSON.load(file)
  end
  channel_data[channel_id]["playlist"] = playlist_name
  open("channel_data.json", 'w') do |file|
    pretty_channel_data = JSON.pretty_generate(channel_data)
    file.write(pretty_channel_data)
  end
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_unlisted_playlist do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  channel_id = event.message.channel.id.to_s
  message = event.message.content
  message.slice!(0, 29)
  playlist_name = message
  playlist_data = plhandler.FindPlayList(
    cookie_file_path: "repcon1.json",
    playlist_name: playlist_name
  )
  if playlist_data.empty? || playlist_data["visibility"] != "unlisted"
    bot.send_message(channel_id,"プレイリストを作成します。しばらくお待ちください。")
    playlist_data = plhandler.MakePlaylist(
      cookie_file_path: "repcon1.json",
      playlist_name: playlist_name,
      playlist_visibility: "unlisted"
    )
  end
  bot.send_message(channel_id,"このチャンネルの動画は以下のプレイリストに登録されます。\n#{playlist_data["url"]}")
  channel_data = File.open("channel_data.json") do |file|
    JSON.load(file)
  end
  channel_data[channel_id]["playlist"] = playlist_name
  open("channel_data.json", 'w') do |file|
    pretty_channel_data = JSON.pretty_generate(channel_data)
    file.write(pretty_channel_data)
  end
  ResetChannelConst()
  a = ""
end

bot.command :morph_reset do |event|
  if not Authorised(event)
    bot.send_message(channel_id,"You are not authorized\nContact the developer")
    break
  end
  channel_id = event.message.channel.id.to_s
  channel_data = File.open("channel_data.json") do |file|
    JSON.load(file)
  end
  event.server.channels.each do |channel|
    if channel_data.has_key?(channel.id.to_s)
      channel_data.delete(channel.id.to_s)
    end
  end
  open("channel_data.json", 'w') do |file|
    pretty_channel_data = JSON.pretty_generate(channel_data)
    file.write(pretty_channel_data)
  end
  bot.send_message(channel_id,"このサーバーでの設定がリセットされました。\n利用を再開するには任意のチャンネルで!morph_set_inputを送信してください")
  ResetChannelConst()
  a = ""
end

bot.command :morph_set_admin do |event|
  channel_id = event.message.channel.id.to_s
  user_id = event.message.user.id.to_s
  if @admin_user_data.has_key?(user_id)
    if @admin_user_data[user_id]["authorized_servers"] == "all"
      new_admin_user_id = event.message.content
      new_admin_user_id.slice!(0, 17)
      new_admin_user_name = bot.user(new_admin_user_id).name
      server_id = event.message.channel.server.id.to_s
      server_name = event.message.channel.server.name
      admin_user_data = File.open("admin_users.json") do |file|
        JSON.load(file)
      end
      if @admin_user_data.has_key?(new_admin_user_id)
        admin_user_data[new_admin_user_id]["authorized_servers"] << server_id
      else
        admin_user_data[new_admin_user_id] = {
          "name" => new_admin_user_name,
          "authorized_servers" => [
            server_id
          ]
        }
      end
      p admin_user_data[new_admin_user_id]
      open("admin_users.json", 'w') do |file|
        pretty_admin_user_data = JSON.pretty_generate(admin_user_data)
        file.write(pretty_admin_user_data)
      end
      bot.send_message(channel_id,"Assigned #{new_admin_user_name} as an administrator of #{server_name}")
      break
    end
    bot.send_message(channel_id,"You are not authorized\nContact the administrator")
    break
  end
  bot.send_message(channel_id,"You are not authorized\nContact the administrator")
  break
end

bot.command :morph_help do |event|
  channel_id_out = event.message.channel.id
  bot.send_message(channel_id_out,"「コマンド一覧」\n!morph_set_input : \nリプレイが投稿されるチャンネルを指定\n!morph_set_output : \n動画送信先を指定する。\n!morph_set_public : \n公開設定を限定公開から公開に変更する。\n!morph_set_playlist : \nチャンネルの動画を公開プレイリストに登録する。\n（例）!morph_set_playlist 至高の戦闘\n!morph_set_unlisted_playlist : \nチャンネルの動画を限定公開プレイリストに登録する。\n!morph_reset : \nサーバーにおけるボットの設定を初期化する。")
end

bot.command :test do |event|
end

bot.run
