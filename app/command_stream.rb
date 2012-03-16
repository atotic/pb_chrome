require 'app/book'
require 'eventmachine'
require 'json'

# High level overview at Architecture.txt:PROBLEM: GROUP EDITING

module PB

# BrowserCommand is a single document operation
# Creating a command causes it to be broadcast
class BrowserCommand < Sequel::Model(:browser_commands)
	
	plugin :timestamps

	many_to_one :book
	
	def self.createAddPhotoCmd(book_id, photo)
		BrowserCommand.create({
			:type => "AddPhoto",
			:book_id => book_id,
			:payload => photo.to_json
		})
	end
	
	def self.createReplacePageCmd(page)
		BrowserCommand.create({
			:type => "ReplacePage",
			:book_id => page.book_id,
			:payload => page.to_json
		})
	end
	
	def self.createAddPageCmd(page, page_position) 
		payload = JSON.parse(page.to_json);
		payload[:previous_page] = page_position - 1
		BrowserCommand.create({
			:type => "AddPage",
			:book_id => page.book_id,
			:payload => payload.to_json
		});
	end

	def self.createDeletePageCmd(page)
		cmd = BrowserCommand.create({
			:type => "DeletePage",
			:book_id => page.book_id,
			:payload => { :page_id => page.id }.to_json
		});
	end
	
	def self.last_command_id(book_id)
		last_cmd = BrowserCommand.filter(:book_id => book_id).order(:id).last
		return last_cmd.id if last_cmd
		return 0;
	end

	def self.restore_from_headers(env)
		stream_id = book_id = nil
		stream_header = env['HTTP_X_SVEGSTREAM']
		last_command_id = env['HTTP_X_SVEG_LASTCOMMANDID'].to_i
		if stream_header
			stream_id, book_id = stream_header.split(";")
			book_id = book_id.to_i
		end
		env['sveg.stream.id'] = stream_id
		env['sveg.stream.last_command'] = last_command_id
		env['sveg.stream.book'] = book_id
		PB.logger.info("sveg.stream.id #{stream_id.to_s}")
	end

	# broadcasts command
	# returns header hash for browser
	def broadcast(env = nil)
		env ||= {}
		CometBroadcaster.broadcast(self, book_id, env['sveg.stream.id'])
#		CmdStreamBroadcaster.broadcast(self, book_id, env['sveg.stream.id'])
		{ 'X-Sveg-LastCommandId' => pk.to_s }
	end
end

class CometBroadcaster
	def self.broadcast(cmd, book_id, exclude_stream)
		query = exclude_stream ? "exclude=#{exclude_stream}" : ""
		http = EventMachine::Protocols::HttpClient.request(
     :host => SvegSettings.comet_host,
     :port => SvegSettings.comet_port,
     :request => "/broadcast/#{cmd.pk}",
     :query_string => query
  	)
		http.callback {|response|
			PB.logger.error "Comet broadcast #{response[:status]}, #{response[:content]}" unless response[:status].eql? 200 
   	}
	end
end

end # module
