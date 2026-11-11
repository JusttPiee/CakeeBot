# Everything the web UI needs from the running bot, in one object.
# cakee.rb fills it in once at startup; tests fill it with pretend objects.
#
#   bot:            the discordrb bot (servers, channels, the bot's own profile)
#   client:         the OpenAI client (only !buildmemory uses it)
#   histories:      the AI chat memory in RAM, one history per channel id (see chat_history.rb)
#   ai_config_path: the file listing the AI channels (ai_config.txt)
#   token:          the secret every API request must send (see web_token.rb)
#   port:           the port the web UI listens on
#   started_at:     when the bot started; the web page uses it to notice a restart has finished
#
# Only set by tests, to replace the parts that would call Discord or end the program:
#   history_loader: loads a channel's recent messages
#   restarter:      restarts the bot
#   build_channels: lists the channels !buildmemory reads
WebContext = Struct.new(:bot, :client, :histories, :ai_config_path, :token, :port, :started_at,
                        :history_loader, :restarter, :build_channels, keyword_init: true)
