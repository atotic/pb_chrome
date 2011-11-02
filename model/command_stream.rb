require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'

require 'model/book'
require 'eventmachine'

module PB

# Command represents 
class ServerCommand
	include DataMapper::Resource
	
	property :id,						Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	property :payload,			Text	# command-specific json payload
	property :type,					String
	belongs_to :book
	
	def self.createAddPhotoCmd(book_id, photo, stream_id)
		payload = photo.to_json()
		cmd = ServerCommand.new({
			:type => "AddPhoto",
			:book_id => book_id,
			:payload => payload
		})
		cmd.save()
		CmdStreamBroadcaster.send_cmd(cmd, book_id, stream_id)
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
		stream_id =  rand(36**6).to_s(36).upcase
		book_id = Integer(book_id)
		@@listeners[book_id] = [] unless @@listeners.has_key? book_id
		@@listeners[book_id].push [ body, stream_id ]
		LOGGER.info("CmdStreamBroadcaster.bind " + stream_id)
		body << stream_id << ";" << " " * 1024 << ";" # standard header
		self.send_commands(body, book_id, stream_id, last_cmd_id)
		self.send("[\"hello\"]", book_id, 0)
	end
	
	def self.send_commands(body, book_id, stream_id, last_cmd_id)
		book_id = Integer(book_id)
		commands = ServerCommand.all(:id.gt => last_cmd_id, :book_id => book_id)
		commands.each { |cmd| self.send_cmd(cmd, book_id, stream_id) }
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
	
	def self.send_cmd(cmd, book_id, stream_id)
		book_id = Integer(book_id)
		msg = {
			:id => cmd.id,
			:type => cmd.type,
			:book_id => book_id,
			:payload => JSON.parse(cmd.payload)
		}.to_json
		self.send msg, book_id, stream_id
	end
	
	# broadcast to everyone except sender
	def self.send( str, book_id, stream_id )
		book_id = Integer(book_id)
		LOGGER.info("CmdStreamBroadcaster.send")
		msg = (StringIO.new << str.length << ";" << str << ";") .string
		streams = @@listeners[book_id] || []
		streams.each do |item| 
			LOGGER.info("Sending to #{item[1]} " + msg[1..10]) unless item[1].eql?(stream_id)
			item[0] << msg unless item[1].eql?(stream_id) 
		end
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