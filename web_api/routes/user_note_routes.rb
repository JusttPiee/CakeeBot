# The "People" tab of the Memory page: what Cake remembers about each person (memory/<server>/users/<id>.md).
#
#   GET    /api/servers/:sid/users              the list of people
#   GET    /api/servers/:sid/users/:uid         one note
#   PUT    /api/servers/:sid/users/:uid         change description, personality, or the personality_off switch
#   DELETE /api/servers/:sid/users/:uid         delete the note (Cake may build a new one later)
#   POST   /api/servers/:sid/users/:uid/facts   add a remembered fact
#   PUT    /api/servers/:sid/items/:item_id     change one fact, or one general note
#   DELETE /api/servers/:sid/items/:item_id     remove it
#
# Everything is done with the bot's own memory functions, inside the server's memory lock,
# and MEMORY.md is rebuilt after every change, exactly like the AI's memory tools do.
require_relative '../../memory_store'
require_relative '../../memory_index'
require_relative '../../tidy_state'
require_relative '../memory_views'

module UserNoteRoutes
  def self.registered(app)
    app.get '/api/servers/:sid/users' do
      json(web_user_list(server_id!))
    end

    app.get '/api/servers/:sid/users/:uid' do
      view = web_user_note(server_id!, discord_id!(:uid))
      view ? json(view) : not_found!
    end

    app.put '/api/servers/:sid/users/:uid' do
      view = web_save_user_note(server_id!, discord_id!(:uid), json_body)
      view ? json(view) : not_found!
    end

    app.delete '/api/servers/:sid/users/:uid' do
      web_delete_user_note(server_id!, discord_id!(:uid)) ? json({ ok: true }) : not_found!
    end

    app.post '/api/servers/:sid/users/:uid/facts' do
      server_id = server_id!
      user_id = discord_id!(:uid)
      text = memory_text!(json_body)
      view = web_add_fact(server_id, user_id, text)
      view ? json(view) : not_found!
    end

    app.put '/api/servers/:sid/items/:item_id' do
      server_id = server_id!
      text = memory_text!(json_body)
      web_change_item(server_id, memory_item_id!, text) ? json({ ok: true }) : not_found!
    end

    app.delete '/api/servers/:sid/items/:item_id' do
      web_remove_item(server_id!, memory_item_id!) ? json({ ok: true }) : not_found!
    end

    app.helpers UserNoteHelpers
  end
end

# Checks done on the request itself, before any memory is touched
module UserNoteHelpers
  # The text of a fact or note from the request. 422 if it is empty or too long.
  def memory_text!(body)
    text = one_line(body["text"])
    halt json({ error: "The text can't be empty." }, 422) if text.empty?
    halt json({ error: "The text can be at most #{REMEMBER_FACT_MAX_CHARS} characters." }, 422) if text.length > REMEMBER_FACT_MAX_CHARS
    text
  end

  # Memory item ids are 8 hex characters (see memory_item_id in memory_items.rb)
  def memory_item_id!
    id = params[:item_id].to_s
    id.match?(/\A[0-9a-f]{8}\z/) ? id : not_found!
  end
end

# --- what each route does. They return nil when the note or item does not exist. ---

# People with a name first (A to Z), then the blank notes !forgetme leaves
def web_user_list(server_id)
  with_server_memory_lock(server_id) do
    people = list_memory_files(server_id, "users").filter_map do |path|
      user_id = File.basename(path, ".md")
      note = read_user_note(server_id, user_id)
      note && user_summary_view(user_id, note)
    end
    people.sort_by { |person| [person[:name].empty? ? 1 : 0, person[:name].downcase, person[:id]] }
  end
end

def web_user_note(server_id, user_id)
  with_server_memory_lock(server_id) do
    note = read_user_note(server_id, user_id)
    note && user_note_view(user_id, note)
  end
end

# Only the fields of the form are changed. The remembered facts are read fresh from the file and kept,
# so a fact Cake saved while the form was open is never lost.
def web_save_user_note(server_id, user_id, form)
  with_server_memory_lock(server_id) do
    note = read_user_note(server_id, user_id)
    next nil if note.nil?

    was_off = note[:personality_off]
    apply_user_note_form(note, form)
    write_user_note(server_id, user_id, note)
    rebuild_memory_index(server_id)
    log "🧠 Web UI turned personality notes back on for user #{user_id} in server #{server_id}" if was_off && !note[:personality_off]
    user_note_view(user_id, note)
  end
end

# With personality notes off there must be no personality text left (the same as forget_my_personality)
def apply_user_note_form(note, form)
  off = form["personality_off"] == true
  note[:personality_off] = off
  note[:description] = off ? "" : one_line(form["description"])
  note[:personality] = off ? "" : without_headings(form["personality"])
end

# Deletes the file, and nothing else: unlike !forgetme, Cake may write a new note about them later
def web_delete_user_note(server_id, user_id)
  deleted = with_server_memory_lock(server_id) do
    next false if read_user_note(server_id, user_id).nil?

    delete_memory_file(server_id, user_note_path(user_id))
    rebuild_memory_index(server_id)
    true
  end
  forget_tidy_state(server_id, user_id) if deleted # takes the lock itself, so it runs after ours is released
  deleted
end

def web_add_fact(server_id, user_id, text)
  with_server_memory_lock(server_id) do
    note = read_user_note(server_id, user_id)
    next nil if note.nil?

    append_remembered_fact(server_id, user_id, note[:name], text)
    rebuild_memory_index(server_id)
    user_note_view(user_id, read_user_note(server_id, user_id))
  end
end

def web_change_item(server_id, item_id, text)
  with_server_memory_lock(server_id) do
    item = find_memory_item(server_id, item_id)
    next false if item.nil?

    change_memory_item(server_id, item, text)
    rebuild_memory_index(server_id)
    true
  end
end

def web_remove_item(server_id, item_id)
  with_server_memory_lock(server_id) do
    item = find_memory_item(server_id, item_id)
    next false if item.nil?

    remove_memory_item(server_id, item)
    rebuild_memory_index(server_id)
    true
  end
end
