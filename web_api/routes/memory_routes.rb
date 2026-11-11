# The other three tabs of the Memory page.
#
#   GET    /api/servers/:sid/general           what people said about others (general.md), newest first
#   GET    /api/servers/:sid/events            planned events, soonest first
#   PUT    /api/servers/:sid/events/:slug      change an event's title, time or details
#   DELETE /api/servers/:sid/events/:slug
#   GET    /api/servers/:sid/summaries         the rolling summary of each AI channel
#   DELETE /api/servers/:sid/summaries/:cid
#
# General notes are changed and removed through /items/:item_id (user_note_routes.rb).
# Summaries can't be edited: compaction rewrites them all the time.
require_relative '../../memory_store'
require_relative '../../memory_index'
require_relative '../../event_notes'
require_relative '../../channel_summary'
require_relative '../memory_views'

EVENT_WHEN_HELP = "The time must look like YYYY-MM-DD or YYYY-MM-DD HH:MM, and be a real date."

module MemoryRoutes
  def self.registered(app)
    app.get '/api/servers/:sid/general' do
      json(web_general_list(server_id!))
    end

    app.get '/api/servers/:sid/events' do
      json(web_event_list(server_id!))
    end

    app.put '/api/servers/:sid/events/:slug' do
      server_id = server_id!
      slug = event_slug!
      form = event_form!(json_body)
      result = web_save_event(server_id, slug, form)
      not_found! if result == :missing
      halt json({ error: "Another event already has this title." }, 422) if result == :taken
      json(result)
    end

    app.delete '/api/servers/:sid/events/:slug' do
      web_delete_event(server_id!, event_slug!) ? json({ ok: true }) : not_found!
    end

    app.get '/api/servers/:sid/summaries' do
      json(web_summary_list(server!))
    end

    app.delete '/api/servers/:sid/summaries/:cid' do
      web_delete_summary(server_id!, discord_id!(:cid)) ? json({ ok: true }) : not_found!
    end

    app.helpers MemoryRouteHelpers
  end
end

module MemoryRouteHelpers
  # An event's file name from the URL. 404 if it could point outside the events folder.
  def event_slug!
    slug = params[:slug].to_s
    slug.empty? || slug.include?("/") || slug.include?("\\") || slug.include?("..") ? not_found! : slug
  end

  # { title:, when:, details: } from the request. 422 if the title is empty or the time is not valid.
  def event_form!(body)
    title = one_line(body["title"])
    when_text = body["when"].to_s.strip
    halt json({ error: "The title can't be empty." }, 422) if title.empty?
    halt json({ error: EVENT_WHEN_HELP }, 422) if parse_event_time(when_text).nil?
    { title: title, when: when_text, details: body["details"].to_s }
  end
end

# --- what each route does ---

# Newest first. Notes of the same day keep the newest-last order of the file, turned around.
def web_general_list(server_id)
  items = with_server_memory_lock(server_id) { general_memory_items(server_id) }
  in_file_order = items.each_with_index.sort_by { |item, position| [item[:date], position] }
  in_file_order.reverse.map { |item, _position| general_item_view(item) }
end

def web_event_list(server_id)
  events = with_server_memory_lock(server_id) { list_event_notes(server_id) }
  events.sort_by { |event| parse_event_time(event[:when]) }.map { |event| event_view(event) }
end

# The event's view, :missing if there is no such event, or :taken if the new title belongs to another event.
# An event's file is named after its title, so a new title means a new file and the old one is removed.
def web_save_event(server_id, slug, form)
  with_server_memory_lock(server_id) do
    old_path = "events/#{slug}.md"
    next :missing if read_memory_file(server_id, old_path).nil?

    new_path = "events/#{event_slug(form[:title])}.md"
    next :taken if new_path != old_path && read_memory_file(server_id, new_path)

    save_event_note(server_id, form[:title], form[:when], form[:details])
    delete_memory_file(server_id, old_path) if new_path != old_path
    rebuild_memory_index(server_id)
    event_view({ path: new_path, title: form[:title], when: form[:when], details: form[:details].strip })
  end
end

def web_delete_event(server_id, slug)
  with_server_memory_lock(server_id) do
    path = "events/#{slug}.md"
    next false if read_memory_file(server_id, path).nil?

    delete_memory_file(server_id, path)
    rebuild_memory_index(server_id)
    true
  end
end

def web_summary_list(server)
  server_id = server.id.to_s
  names = server.text_channels.to_h { |channel| [channel.id.to_s, channel.name] }
  with_server_memory_lock(server_id) do
    list_memory_files(server_id, "channels").map do |path|
      channel_id = File.basename(path, ".md")
      summary_view(channel_id, names[channel_id], parse_note(read_memory_file(server_id, path)))
    end
  end
end

# Summaries are not in MEMORY.md, so there is no index to rebuild
def web_delete_summary(server_id, channel_id)
  with_server_memory_lock(server_id) do
    path = channel_summary_path(channel_id)
    next false if read_memory_file(server_id, path).nil?

    delete_memory_file(server_id, path)
    true
  end
end
