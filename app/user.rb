require 'app/book'
require 'sequel'
module PB
	
class User < Sequel::Model

 	plugin :timestamps

	one_to_many :books
	one_to_many :photos

	def save_to_session(env, expire = nil)
		expire ||= Time.now + 1.days.to_i
		env['rack.session']['user_id'] = self.pk
		env['rack.session']['user_id_expires'] = expire.to_i
		env['sveg.user'] = self
	end

	def self.restore_from_session(env)
		user_id = env['rack.session']['user_id'].to_i
		expire = env['rack.session']['user_id_expires']
		expire_time = Time.at(expire.to_i)
		return "user not logged in" unless expire_time > Time.now
		env['sveg.user'] = self[user_id]
	end

	def login(env)
		save_to_session(env)
	end

	def self.logout(env)
		env['rack.session'].delete('user_id')
		env['rack.session'].delete('user_id_expires')
	end

	def to_s
		"#{self.display_name}:#{self.pk}"
	end

end


#
# Auth classes
# each auth instance represents a login via corresponding service
# 

# AuthLogin is a simple username/pw login in theory
# For now, it is just username.
class AuthLogin < Sequel::Model(:auth_logins)
	
	plugin :timestamps

#	property :login_id,			String, :key => true
#	property :created_at,		DateTime
#	property :updated_at,		DateTime
# common auth properties
#	property :user_id,			Integer		# pointer to User record
#	property :created_on,		DateTime, :default => lambda { |r,p| Time.now }
#	property :last_login,		DateTime, :default => lambda { |r,p| Time.now }
	
	set_primary_key :login_id

	many_to_one :user # user this authoricazion is for

	# creates login
	def self.create_with_user(login_id)
		DB.transaction do
			user = User.new({:display_name => login_id})
			user.is_administrator = true if login_id.eql? "atotic"
			user.save
			unrestrict_primary_key
			auth = AuthLogin.new({:login_id => login_id, :user_id => user.id} )
			auth.save
			restrict_primary_key
			auth
		end
	end

	def login
	end
end

end
