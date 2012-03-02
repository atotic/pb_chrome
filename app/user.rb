require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'

require 'app/book'

module PB
	
class User
  include DataMapper::Resource
  
  property :id,        		Serial        # primary serial key
	property :created_at,		DateTime
	property :updated_at,		DateTime

  property :display_name,	String
 	property :is_administrator,   Boolean, :default => false

	has n, :books
	has n, :photos

	def save_to_session(env, expire = nil)
		expire ||= Time.now + 1.days.to_i
		env['rack.session']['user_id'] = self['id']
		env['rack.session']['user_id_expires'] = expire.to_i
		env['sveg.user'] = self
	end

	def self.restore_from_session(env)
		user_id = env['rack.session']['user_id'].to_i
		expire = env['rack.session']['user_id_expires']
		expire_time = Time.at(expire.to_i)
		return "user not logged in" unless expire_time > Time.now
		env['sveg.user'] = PB::User.get(user_id)
	end

	def login(env)
		save_to_session(env)
	end

	def self.logout(env)
		env['rack.session'].delete('user_id')
		env['rack.session'].delete('user_id_expires')
	end
end

#
# Auth classes
# each auth instance represents a login via corresponding service
# 

# AuthLogin is a simple username/pw login in theory
# For now, it is just username.
class AuthLogin
	include DataMapper::Resource
	
	property :login_id,			String, :key => true
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	belongs_to :user	# user this authorization is for

	# common auth properties
#	property :user_id,			Integer		# pointer to User record
	property :created_on,		DateTime, :default => lambda { |r,p| Time.now }
	property :last_login,		DateTime, :default => lambda { |r,p| Time.now }

	# creates login
	def self.create(login_id)
		user = User.new({:display_name => login_id})
		user.is_administrator = true if login_id.eql? "atotic"
		user.save
		auth = AuthLogin.new({:login_id => login_id, :user_id => user.id} )
		auth.save
		auth
	end

	def login
	end
end

end
