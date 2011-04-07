require 'dm-validations'
require 'dm-core'
require 'dm-migrations'


class User
  include DataMapper::Resource
  
  property :id,        		Serial        # primary serial key
  property :display_name,	String
 	property :is_administrator,   Boolean, :default => false

end

#
# Auth classes
# each auth instance represents a login via corresponding service
# 

class AuthLogin
	include DataMapper::Resource
	
	property :login_id,			String, :key => true
	
	# common auth properties
	property :user_id,			Integer		# pointer to User record
	property :created_on,		DateTime, :default => lambda { |r,p| Time.now }
	property :last_login,		DateTime, :default => lambda { |r,p| Time.now }

end