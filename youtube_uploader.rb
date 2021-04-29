require "selenium-webdriver"
require "yaml"
require "json"

class YouTubeUploader
  attr_accessor :cookie_file_path, :video_path, :video_title, :video_description, :visibility, :playlist_name

  def StartUpload(args)
    @cookie_file_path = args[:cookie_file_path]
    @video_path = args[:video_path]
    @video_title = args[:video_title]
    @video_description = args[:video_description]
    @visibility = args[:visibility]
    @playlist_name = args[:playlist_name]
    options = Selenium::WebDriver::Chrome::Options.new
    # options.add_argument('--headless')
    @driver = Selenium::WebDriver.for :chrome, options: options
    @wait = Selenium::WebDriver::Wait.new(:timeout => 40)
    Login()
    return Upload()
  end

  def Login()
    @driver.get('https://youtube.com')
    cookies_str = open(@cookie_file_path, 'r') do |f|
      JSON.load(f)
    end
    cookies_str.each do |cookie_str|
      cookie_symbol = cookie_str.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
      cookie_symbol.delete(:sameSite)
      @driver.manage.add_cookie(cookie_symbol)
    end
    @driver.get('https://youtube.com')
    account_icon = @driver.find_element(:xpath, '//*[@id="img"]')
    account_icon.click
    sleep 1
    account_name = @driver.find_element(:xpath, '//*[@id="account-name"]').text
    p "logged in as #{account_name}"
  end

  def Upload()
    @driver.get('https://www.youtube.com/upload')
    sleep 1
    absolute_video_path = Dir.pwd + "/" + @video_path
    @driver.find_element(:xpath, "//input[@type='file']").send_keys absolute_video_path
    sleep 4
    title_field = @driver.find_element(:id, "textbox")
    title_field.click
    title_field.send_keys(:control, 'a')
    title_field.send_keys(@video_title)
    description_container = @driver.find_element(:id, 'description-container')
    description_field = description_container.find_element(:id, 'textbox')
    description_field.click
    description_field.clear
    description_field.send_keys @video_description
    sleep 1
    kids_section = @driver.find_element(:name, 'NOT_MADE_FOR_KIDS')
    kids_section.find_element(:id, 'radioLabel').click
    @driver.find_element(:id, 'next-button').click
    @driver.find_element(:id, 'next-button').click
    @driver.find_element(:id, 'next-button').click
    if visibility == "public"
      public_main_button = @driver.find_element(:name, 'PUBLIC')
      public_main_button.find_element(:id, 'radioLabel').click
    elsif visibility == "unlisted"
      unlisted_main_button = @driver.find_element(:name, 'UNLISTED')
      unlisted_main_button.find_element(:id, 'radioLabel').click
    end
    video_id = GetVideoID()
    status_container = @driver.find_element(:xpath, '/html/body/ytcp-uploads-dialog/tp-yt-paper-dialog/div/ytcp-animatable[2]/div/div[1]/ytcp-video-upload-progress/span')
    while true
      if not status_container.text.include?('アップロード中')
        break
      else
        p status_container.text
        sleep 1
      end
    end
    done_button = @driver.find_element(:id, 'done-button')
    while true
      if done_button.attribute('aria-disabled') == "false"
        done_button.click
        break
      else
        sleep 1
      end
    end
    @wait.until do
      @driver.find_element(:xpath, '/html/body/ytcp-uploads-still-processing-dialog/ytcp-dialog/tp-yt-paper-dialog').displayed?
    end
    p @playlist_name
    if not @playlist_name.empty?
      sleep 1
      @driver.get("https://studio.youtube.com/video/#{video_id}/edit")
      sleep 3
      playlist_dropdown = @driver.find_element(:xpath, '//*[@id="basics"]/div[4]/div[3]/div[1]/ytcp-video-metadata-playlists/ytcp-text-dropdown-trigger/ytcp-dropdown-trigger/div')
      playlist_dropdown.click
      sleep 1
      playlists = @driver.find_elements(:xpath, '//*[@id="items"]/ytcp-ve')
      playlists.each_with_index do |playlist, i|
        if playlist.text == @playlist_name
          playlist_checkbox = @driver.find_element(:id, "checkbox-#{i}")
          playlist_checkbox.click
          sleep 1
          break
        end
      end
      playlist_close_btn = @driver.find_element(:xpath, '//*[@id="dialog"]/div[2]/ytcp-button[3]')
      playlist_close_btn.click
      sleep 1
      save_btn = @driver.find_element(:xpath, '//*[@id="save"]/div')
      save_btn.click
      sleep 1
    end
    @driver.get('https://www.youtube.com')
    Quit()
    return video_id
  end

  def GetVideoID()
    while true
      video_url_container = @driver.find_element(:xpath, "//span[@class='video-url-fadeable style-scope ytcp-video-info']")
      video_url_element = video_url_container.find_element(:xpath, "//a[@class='style-scope ytcp-video-info']")
      video_id = video_url_element.attribute('href').split('/')[-1]
      if video_id != "youtu.be"
        break
      end
    end
    return video_id
  end

  def Quit()
    @driver.quit
  end
end

class YoutubePlaylistHandler
  attr_accessor :cookie_file_path, :playlist_name, :playlist_visibility

  def FindPlayList(args)
    @cookie_file_path = args[:cookie_file_path]
    @playlist_name = args[:playlist_name]
    @playlist_visibility = args[:playlist_visibility] || "public"
    SetDriver()
    p "set variables"
    Login()
    playlist_data = Find()
    @driver.quit
    return playlist_data
  end

  def MakePlaylist(args)
    @cookie_file_path = args[:cookie_file_path]
    @playlist_name = args[:playlist_name]
    @playlist_visibility = args[:playlist_visibility] || "public"
    SetDriver()
    Login()
    playlist_url = Start()
    @driver.quit
    return playlist_url
  end

  def SetDriver()
    options = Selenium::WebDriver::Chrome::Options.new
    # options.add_argument('--headless')
    @driver = Selenium::WebDriver.for :chrome, options: options
  end

  def Login()
    @driver.get('https://youtube.com')
    cookies_str = open(@cookie_file_path, 'r') do |f|
      JSON.load(f)
    end
    cookies_str.each do |cookie_str|
      cookie_symbol = cookie_str.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
      cookie_symbol.delete(:sameSite)
      @driver.manage.add_cookie(cookie_symbol)
    end
    @driver.get('https://youtube.com')
    account_icon = @driver.find_element(:xpath, '//*[@id="img"]')
    account_icon.click
    sleep 1
    account_name = @driver.find_element(:xpath, '//*[@id="account-name"]').text
    p "logged in as #{account_name}"
    @driver.get('https://studio.youtube.com/channel/*/playlists')
  end

  def Find()
    sleep 1
    playlists = @driver.find_elements(:xpath, "/html/body/ytcp-app/ytcp-entity-page/div/div/main/div/ytcp-animatable[56]/ytcp-playlist-section/ytcp-playlist-section-content/div/ytcp-playlist-row")
    playlists.each do |playlist|
      playlist_name = playlist.find_element(:tag_name, "h3").text
      p playlist_name
      if playlist_name == @playlist_name
        playlist_visibility_jp = playlist.text.split("\n")[3]
        if playlist_visibility_jp == "公開"
          playlist_visibility = "public"
        elsif playlist_visibility_jp == "限定公開"
          playlist_visibility = "unlisted"
        else
          playlist_visibility = "private"
        end
        playlist_url = playlist.find_element(:tag_name, "div").find_element(:tag_name, "a").attribute("href")
        playlist_data = {"name" => @playlist_name, "url" => playlist_url, "visibility" => playlist_visibility}
        return playlist_data
      end
    end
    return ""
  end

  def Start()
    @driver.get('https://studio.youtube.com/channel/*/playlists')
    new_playlist_button = @driver.find_element(:xpath, "/html/body/ytcp-app/ytcp-entity-page/div/div/main/div/ytcp-animatable[1]/div[1]/ytcp-button")
    new_playlist_button.click
    playlsit_name_field = @driver.find_element(:xpath, "/html/body/ytcp-playlist-creation-dialog/ytcp-dialog/tp-yt-paper-dialog/div[2]/div/div[1]/ytcp-form-textarea/div/textarea")
    playlsit_name_field.click
    # playlsit_name_field.send_keys(:control, 'a')
    # playlsit_name_field.clear
    playlsit_name_field.send_keys(@playlist_name)
    p "playlist name set"
    if @playlist_visibility == "unlisted"
      playlist_visibility_dropdown = @driver.find_element(:xpath, '//*[@id="create-playlist-form"]/div/ytcp-text-dropdown-trigger/ytcp-dropdown-trigger/div')
      playlist_visibility_dropdown.click
      sleep 1
      playlsit_unlisted = @driver.find_element(:xpath, '//*[@id="text-item-2"]/ytcp-ve/div')
      playlsit_unlisted.click
      p "playlist set as unlisted"
    end
    playlist_create_button = @driver.find_element(:xpath, "/html/body/ytcp-playlist-creation-dialog/ytcp-dialog/tp-yt-paper-dialog/div[2]/div/div[2]/ytcp-button[2]")
    playlist_create_button.click
    sleep 10
    playlist_url = @driver.find_element(:xpath, '//*[@id="row-container"]/div[1]/div/a').attribute("href")
    p "playlist created"
    playlist_data = {"name" => @playlist_name, "url" => playlist_url, "visibility" => playlist_visibility}
    return playlist_data
  end
end
