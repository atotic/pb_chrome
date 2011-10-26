require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'

require 'model/book'
require 'eventmachine'

module PB

# Command represents 
class Command
	include DataMapper::Resource
	
	property :id,					 Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	property :cmd,					Text
	
	belongs_to :book
end

# Event machine classes
# 
# Broadcasts command to all open streams
# based on https://github.com/rkh/presentations/blob/realtime-rack/example.rb
# and http://code.google.com/p/jquery-stream/wiki/ServerSideProcessing
class CmdStreamBroadcaster
	@@listeners = Hash.new
	
	def self.bind(subscriber, id)	# subscriber is DeferrableBody
		LOGGER.info("CmdStreamBroadcaster.bind " + id)
		raise "No id" unless id
		raise "Duplicate listener" if @@listeners.has_key? id
		@@listeners[id] = subscriber
		subscriber << id << ";" << " " * 1024 << ";" # standard header
	end
	
	def self.unbind(subscriber)
		key = @@listeners.keys.select { |k| @@listeners[k].eql? subscriber }
		LOGGER.info("CmdStreamBroadcaster.unbind " + (key.empty? ? "" : key[0]))
		@@listeners.delete(key[0]) unless key.empty?
	end
	
	def self.send( str, broadcaster )
		LOGGER.info("CmdStreamBroadcaster.send")
		msg = (StringIO.new << str.length << ";" << str << ";") .string
		@@listeners.each_pair {  |k,v| v << msg unless k.eql?(broadcaster) }
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