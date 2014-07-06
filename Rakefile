require "./app"

namespace :import do
  desc "Import the history of a Slack channel into the bot"
  task :channel, :channel_name do |t, args|
    if args.channel_name.nil?
      puts "You need to specify the name of the channel you wish to import, e.g. rake import:channel[random]"
    else
      puts "Importing channel #{args.channel_name} to #{ENV["RACK_ENV"]} (this will take a while)"
      channel_id = get_channel_id(args.channel_name)
      import_history(channel_id)
    end
  end
end
