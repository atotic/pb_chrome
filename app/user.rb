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

end

end
