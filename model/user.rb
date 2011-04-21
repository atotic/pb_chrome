require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'

require 'model/book'

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

class AuthLogin
	include DataMapper::Resource
	
	property :login_id,			String, :key => true
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	# common auth properties
	property :user_id,			Integer		# pointer to User record
	property :created_on,		DateTime, :default => lambda { |r,p| Time.now }
	property :last_login,		DateTime, :default => lambda { |r,p| Time.now }

end