# The bot's own custom emojis (Discord "application emojis").
# Cake writes an emoji as :name: in its text. Only the text sent to Discord is converted to <:name:id>,
# so the history keeps the short form. Everything here fails quietly: with no emojis Cake just answers without them.
#
# Notes (what each emoji means, how often Cake used it) are kept in memory/emoji_notes.json:
#   { "<id>" => { "name" => "sad", "description" => "feeling sad", "uses" => 3 } }
require 'json'
require 'fileutils'
require_relative './config'
require_relative './token_usage'
require_relative './tools/look_at_image' # download_image

EmojiEntry = Struct.new(:id, :name, :animated, :description, :uses, keyword_init: true)

# :name: that is not part of <:name:id>, a URL or a time like 10:30:45
EMOJI_NAME_PATTERN = %r{(?<![<\w/]):([A-Za-z0-9_]{2,32}):(?!\d)}

class EmojiLibrary
  def initialize(notes_path: File.join(MEMORY_DIR, 'emoji_notes.json'))
    @notes_path = notes_path
    @lock = Mutex.new # guards every instance variable below
    @emojis = {} # id => { name:, animated: }
    @notes = read_notes
    @favourites = nil # [made_at, count, entries]
    @failed_ids = {} # emojis that could not be described in this run: not tried again until the bot restarts
  end

  # Fetches the emoji list (fetcher.call gives [{ id:, name:, animated: }]). Returns how many there are.
  # The fetch happens outside the lock. If it fails, the old list stays.
  def refresh(fetcher)
    found = fetcher.call.to_a
    @lock.synchronize { found.empty? ? keep_old_list : replace_emojis(found) }
  rescue StandardError => e
    log "😀 emoji refresh failed: #{e.message}"
    @lock.synchronize { @emojis.length }
  end

  def entries
    @lock.synchronize { entries_unlocked }
  end

  def empty?
    @lock.synchronize { @emojis.empty? }
  end

  # "<:sad:123>" or "<a:dance:456>", or nil for an unknown name
  def discord_form(name)
    @lock.synchronize { discord_form_unlocked(name) }
  end

  # Replaces :name: with the Discord form, for known names only
  def to_discord(text)
    @lock.synchronize do
      text.to_s.gsub(EMOJI_NAME_PATTERN) { |match| discord_form_unlocked(Regexp.last_match(1)) || match }
    end
  end

  # Counts every known :name: in the AI's text, then saves
  def record_uses(text)
    @lock.synchronize do
      ids = known_ids_in(text.to_s)
      return if ids.empty?

      ids.each { |id| note_for(id)['uses'] += 1 }
      save_notes
    end
  end

  # The most used emojis, most used first, then by name. Rebuilt at most every EMOJI_FAVOURITES_REFRESH_SECONDS.
  def favourites(count, now: Time.now)
    @lock.synchronize do
      made_at, made_count, list = @favourites
      return list if list && made_count == count && now - made_at < EMOJI_FAVOURITES_REFRESH_SECONDS

      list = entries_unlocked.sort_by { |entry| [-entry.uses, entry.name] }.first(count)
      @favourites = [now, count, list]
      list
    end
  end

  def missing_descriptions
    @lock.synchronize { entries_unlocked.select { |entry| entry.description.to_s.empty? } }
  end

  def set_description(id, text)
    @lock.synchronize do
      return unless @emojis.key?(id.to_i)

      note_for(id.to_i)['description'] = text.to_s
      save_notes
    end
  end

  # Describes every emoji that has no description yet. One failure is logged and skipped.
  # The describer talks to OpenAI, so it runs outside the lock.
  # An emoji that fails (or gets an empty answer) is not tried again until the bot restarts.
  def describe_missing(client, describer: method(:describe_emoji_image))
    missing_descriptions.each do |entry|
      next if @lock.synchronize { @failed_ids.key?(entry.id) }

      describe_one(client, entry, describer)
    end
  end

  private

  def describe_one(client, entry, describer)
    text = describer.call(client, entry).to_s.strip
    raise 'empty description' if text.empty?

    set_description(entry.id, text)
  rescue StandardError => e
    @lock.synchronize { @failed_ids[entry.id] = true }
    log "😀 could not describe :#{entry.name}: #{e.message}"
  end

  # --- state (call only while holding the lock) ---

  # Discord gave nothing: probably a hiccup, so the old list and notes stay. Returns how many emojis there are.
  def keep_old_list
    log '😀 emoji refresh got an empty list, keeping the old one' unless @emojis.empty?
    @emojis.length
  end

  def replace_emojis(found)
    @emojis = found.to_h { |emoji| [emoji[:id].to_i, { name: emoji[:name].to_s, animated: emoji[:animated] ? true : false }] }
    @notes.select! { |id, _| @emojis.key?(id.to_i) } # notes of deleted emojis go away
    @emojis.each { |id, emoji| note_for(id)['name'] = emoji[:name] }
    @favourites = nil
    save_notes
    found.length
  end

  def entries_unlocked
    @emojis.map { |id, emoji| entry_for(id, emoji) }.sort_by(&:name)
  end

  def entry_for(id, emoji)
    note = @notes[id.to_s] || {}
    EmojiEntry.new(id: id, name: emoji[:name], animated: emoji[:animated],
                   description: note['description'].to_s, uses: note['uses'].to_i)
  end

  def note_for(id)
    note = (@notes[id.to_s] ||= {})
    note['uses'] = note['uses'].to_i
    note
  end

  def discord_form_unlocked(name)
    id, emoji = @emojis.find { |_, candidate| candidate[:name] == name }
    return nil if id.nil?

    "<#{emoji[:animated] ? 'a' : ''}:#{name}:#{id}>"
  end

  def known_ids_in(text)
    text.scan(EMOJI_NAME_PATTERN).flatten.filter_map do |name|
      @emojis.find { |_, emoji| emoji[:name] == name }&.first
    end
  end

  # --- the notes file ---

  # A broken or missing file reads as empty
  def read_notes
    return {} unless File.file?(@notes_path)

    notes = JSON.parse(File.read(@notes_path, encoding: 'UTF-8'))
    notes.is_a?(Hash) ? notes.select { |_, note| note.is_a?(Hash) } : {}
  rescue JSON::ParserError, SystemCallError
    {}
  end

  # Written to a temp file first, then renamed, so a crash never leaves half a file
  def save_notes
    FileUtils.mkdir_p(File.dirname(@notes_path))
    temp_path = "#{@notes_path}.tmp"
    File.write(temp_path, JSON.pretty_generate(@notes), encoding: 'UTF-8')
    File.rename(temp_path, @notes_path)
  rescue SystemCallError => e
    log "😀 could not save emoji notes: #{e.message}"
  end
end

# --- describing a picture ---

DESCRIBE_EMOJI_PROMPT = 'In at most 8 words, what feeling or reaction does this Discord emoji named :%s: show? ' \
                        'Answer with the words only.'.freeze
EMOJI_DESCRIPTION_MAX_CHARS = 80

# What the emoji means, from its picture. Raises when the download or OpenAI fails.
# Needs ai_chat.rb loaded for answer_text (cakee.rb loads it before any refresh runs).
# It is not required here, because ai_chat.rb uses EMOJIS and that would be a require cycle.
def describe_emoji_image(client, entry, downloader: method(:download_image))
  data_url = downloader.call("https://cdn.discordapp.com/emojis/#{entry.id}.png")
  raise data_url if data_url.start_with?('Error:')

  response = client.responses.create(parameters: emoji_description_request(entry, data_url))
  log_token_usage('emoji', response)
  answer_text(response).strip[0, EMOJI_DESCRIPTION_MAX_CHARS]
end

def emoji_description_request(entry, data_url)
  { model: OPENAI_MODEL,
    input: [{ role: 'user',
              content: [{ type: 'input_text', text: format(DESCRIBE_EMOJI_PROMPT, entry.name) },
                        { type: 'input_image', image_url: data_url, detail: 'low' }] }],
    reasoning: { effort: 'none' },
    store: false }
end

# --- Discord and the bot-wide library ---

# A function that lists the bot's emojis the way EmojiLibrary#refresh wants them
def application_emoji_fetcher(bot)
  lambda do
    bot.application_emojis.map { |emoji| { id: emoji.id, name: emoji.name, animated: emoji.animated? } }
  end
end

EMOJIS = EmojiLibrary.new

# Keeps the library fresh: refresh, describe new emojis, sleep, repeat. Errors are logged, the loop continues.
def start_emoji_refresh(bot, client, library = EMOJIS)
  Thread.new do
    loop do
      begin
        library.refresh(application_emoji_fetcher(bot))
        library.describe_missing(client)
      rescue StandardError => e
        log "😀 emoji refresh loop: #{e.message}"
      end
      sleep emoji_refresh_wait(library)
    end
  end
end

# Seconds until the next refresh: soon while there are still no emojis (a hiccup at startup), else the normal wait
def emoji_refresh_wait(library)
  library.empty? ? EMOJI_RETRY_SECONDS : EMOJI_REFRESH_MINUTES * 60
end
