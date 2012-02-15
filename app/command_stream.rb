require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'

require 'app/book'
require 'eventmachine'
require 'json'

# High level overview at Architecture.txt:PROBLEM: GROUP EDITING

module PB

# ServerCommand is a single document operation
# Creating a command causes it to be broadcast
class ServerCommand
	include DataMapper::Resource
	
	property :id,						Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	property :payload,			Text, :lazy => false	# command-specific json payload
	property :type,					String
	belongs_to :book
	
	def self.createAddPhotoCmd(book_id, photo, exclude_stream)
		cmd = ServerCommand.new({
			:type => "AddPhoto",
			:book_id => book_id,
			:payload => photo.to_json
		})
		cmd.save()
		CmdStreamBroadcaster.broadcast(cmd, book_id, exclude_stream)
		cmd.id
	end
	
	def self.createReplacePageCmd(page, exclude_stream)
		cmd = ServerCommand.new({
			:type => "ReplacePage",
			:book_id => page.book_id,
			:payload => page.to_json
		})
		cmd.save
		CmdStreamBroadcaster.broadcast(cmd, page.book_id, exclude_stream)
		cmd.id		
	end
	
	def self.createAddPageCmd(page, page_position, exclude_stream) 
		payload = JSON.parse(page.to_json);
		payload[:previous_page] = page_position - 1
		cmd = ServerCommand.new({
			:type => "AddPage",
			:book_id => page.book_id,
			:payload => payload.to_json
		});
		cmd.save
		CmdStreamBroadcaster.broadcast(cmd, page.book_id, exclude_stream)
		cmd.id
	end

	def self.createDeletePageCmd(page, exclude_stream)
		cmd = ServerCommand.new({
			:type => "DeletePage",
			:book_id => page.book_id,
			:payload => { :page_id => page.id }.to_json
		});
		cmd.save
		CmdStreamBroadcaster.broadcast(cmd, page.book_id, exclude_stream)
		cmd.id
	end
	
	def self.last_command_id(book_id)
		last_cmd = ServerCommand.last(:book_id => book_id)
		return last_cmd.id if last_cmd
		return 0;
	end
end

# Event machine classes
# 
# Broadcasts command to all open streams
# based on https://github.com/rkh/presentations/blob/realtime-rack/example.rb
# and http://code.google.com/p/jquery-stream/wiki/ServerSideProcessing
class CmdStreamBroadcaster
	@@listeners = Hash.new # { :book_id => [ [body, stream_id]* ]  }
	
	def self.bind(body, book_id, last_cmd_id)	# subscriber is DeferrableBody
		book_id = Integer(book_id)
		stream_id =  rand(36**6).to_s(36).upcase
		@@listeners[book_id] = [] unless @@listeners.has_key? book_id
		@@listeners[book_id].push [ body, stream_id ]
		LOGGER.info("CmdStreamBroadcaster.bind " + stream_id)
		
		# send standard js streaming header
		body << stream_id << ";" << " " * 1024 << ";" 
		# send all the outstanding commands 
		commands = ServerCommand.all(:id.gt => last_cmd_id, :book_id => book_id)
		commands.each { |cmd| body << self.encode_msg(cmd) }
		# tell client they are up to date
		self.send_stream_up_to_date(book_id, body);
	end
	
	def self.unbind(book_id, body)
		book_id = Integer(book_id)
		stream_id = "";
		book_listens = @@listeners[book_id]
		book_listens.delete_if do |item| 
			stream_id = item[1] if item[0] == body 
			item[0] == body
		end
		LOGGER.info("CmdStreamBroadcaster.unbind " + stream_id)
	end

	# broadcast msg to (everyone except exclude_id) listening on book_id
	# msg is String||ServerCommand
	def self.broadcast( msg, book_id, exclude_id )
		LOGGER.info("CmdStreamBroadcaster.send")
		book_id = Integer(book_id)
		encoded_msg = self.encode_msg(msg)
		streams = @@listeners[Integer(book_id)] || []
		streams.each do |item| 
#			LOGGER.info("Sending to #{item[1]} " + encoded_msg[1..10]) unless item[1].eql?(exclude_id)
			item[0] << encoded_msg unless item[1].eql?(exclude_id) 
		end
	end

private
	def self.encode_msg(msg)
		msg = self.encode_command(msg) if msg.kind_of? PB::ServerCommand
		(StringIO.new << msg.length << ";" << msg << ";") .string
	end
	
	def self.encode_command(cmd)
		{
			:id => cmd.id,
			:type => cmd.type,
			:book_id => cmd.book_id,
			:payload => JSON.parse(cmd.payload)
		}.to_json		
	end
	
	def self.send_stream_up_to_date(book_id, body) 
			s = {
				:type => "StreamUpToDate",
				:book_id => book_id
			}.to_json
			body << self.encode_msg(s)
	end
	
end

class DeferrableBody
  include EventMachine::Deferrable

  def call(body)
    body.each do |chunk|
      @body_callback.call(chunk)
    end
  end

  def each(&blk)
    @body_callback = blk
  end
  
  def <<(str)
  	@body_callback.call(str)
  	self
  end

end

end # module