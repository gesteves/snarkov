require "./app"

namespace :import do
  desc "Import the history of a Slack channel into the bot"
  task :channel, :channel_id do |t, args|
    if args.channel_id.nil?
      puts "You need to specify the ID of the channel you wish to import, e.g. rake import:channel[abc123]"
    else
      puts "Importing Channel #{args.channel_id}"
      import_history(args.channel_id)
    end
  end
end
