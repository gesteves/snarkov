require "./app"

namespace :import do
  desc "Import the history of a Slack channel into the bot"
  task :channel do
    if ENV["CHANNELS"].nil?
      puts "You need to specify the name of the channels you wish to import, e.g. rake import:channel CHANNELS=\"#random\""
    else
      options = {}
      start_time = Time.now
      channels = ENV["CHANNELS"].split(",")
      options[:user_id] = get_slack_user_id(ENV["USERNAME"]) unless ENV["USERNAME"].nil?
      options[:oldest] = (start_time - (60 * 60 * 24 * ENV["DAYS"].to_i)).to_i unless ENV["DAYS"].nil?
      channels.each do |channel|
        puts "\nImporting channel #{channel.strip} to #{ENV["RACK_ENV"]} (this will take a while)\n\n"
        channel_id = get_channel_id(channel.strip)
        import_history(channel_id, options)
      end
      puts "Completed in #{Time.now - start_time} seconds"
    end
  end
end

task :flush do
  start_time = Time.now
  puts "Flushing redis..."
  $redis.flushall
  puts "Completed in #{Time.now - start_time} seconds"
end

task :reset => ['flush', 'import:channel']
