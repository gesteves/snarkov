require "./app"

namespace :import do
  desc "Import the history of a Slack channel into the bot"
  task :channel do
    if ENV["CHANNELS"].nil?
      puts "You need to specify the name of the channels you wish to import, e.g. rake import:channel CHANNELS=\"#random\""
    else
      start_time = Time.now
      channels = ENV["CHANNELS"].split(",")
      user_id = get_slack_user_id(ENV["USERNAME"]) unless ENV["USERNAME"].nil?
      if ENV["DAYS"].nil?
        oldest = 0
      else
        oldest = (start_time - (60 * 60 * 24 * ENV["DAYS"].to_i)).to_i
      end
      channels.each do |channel|
        puts "Importing channel #{channel.strip} to #{ENV["RACK_ENV"]} (this will take a while)"
        channel_id = get_channel_id(channel.strip)
        import_history(channel_id, nil, user_id, oldest)
      end
      puts "Completed in #{Time.now - start_time} seconds"
    end
  end
end

task :tweet do
  tweet(build_markov)
end