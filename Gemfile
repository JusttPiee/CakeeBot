source 'https://rubygems.org'

ruby '>= 3.3' # Matches the README requirement (Ruby 3.3+)

# '~> 3.8' means: any 3.x version from 3.8 up, but never 4.0 (which could break the bot)
gem 'discordrb', '~> 3.8' # Discord bot framework
gem 'ruby-openai', '~> 8.3' # OpenAI API https://github.com/alexrudall/ruby-openai
gem 'dotenv', '~> 3.2' # Loads secrets from a local .env file into ENV
gem 'sinatra', '~> 4.1' # Small web framework: the JSON API of the web UI (web_api/)
gem 'puma', '>= 6.4' # The web server that runs the Sinatra app, on a thread inside the bot

group :test do
  gem 'rack-test', '~> 2.1' # Calls the web API in tests without starting a server
  gem 'minitest', '~> 5.20' # Unit tests in test/ (run: bundle exec ruby test/run_all.rb)
end
