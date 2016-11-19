require "./app"

namespace :ingest do
  desc "Ingest the history of a Slack channel into the bot"
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

  desc "Empties the entire database"
  task :empty do
    start_time = Time.now
    puts "Emptying redis..."
    $redis.flushall
    puts "Completed in #{Time.now - start_time} seconds"
  end

  desc "Empties the entire database and reingests the channel"
  task :reingest => ['empty', 'channel']
end

task :topic do
  if ENV["CHANNEL"].nil?
    puts "You need to specify the name of the channel you wish to set the topic for."
  elsif !Time.now.saturday? && !Time.now.sunday? && rand > 0.5
    start_time = Time.now
    channel_id = get_channel_id(ENV["CHANNEL"].strip)
    topic = build_markov
    puts "Setting topic in #{ENV['CHANNEL']} to “#{topic}”"
    set_topic(channel_id, topic)
    puts "Completed in #{Time.now - start_time} seconds"
  end
end
