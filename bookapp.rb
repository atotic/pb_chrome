require 'rubygems'
require 'sinatra/base'
require 'erb'
require 'logger'
require 'json'
require 'base64'
require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-transactions'
require 'data_objects'

require 'ruby-debug'

require 'book_model'

class ColorLogger < Logger
	def initialize()
		super(STDOUT)
		self.datetime_format = ""
	end

	def warn(msg)
		printf STDOUT, "\033[33m";super;printf STDOUT, "\033[0m"
	end

	def error(msg)
		printf STDOUT, "\033[31m";super;printf STDOUT, "\033[0m"
	end
end

class SvegLogger
	FORMAT = %{ %s"%s %s%s %s" %s %0.4f\n}
	def initialize(app)
		@app = app
		@logger = STDERR
	end

	def call(env)
		began_at = Time.now
		status, header, body = @app.call(env)
		header = Rack::Utils::HeaderHash.new(header)
		log(env, status, header, began_at)
		[status, header, body]
	end

	def log(env, status, header, began_at)
		now = Time.now

		logger = @logger || env['rack.errors']
		return if env['sinatra.static_file']
		STDERR.write "HTTP ERROR" if status >= 400
		logger.write FORMAT % [
			env["REMOTE_USER"] || "-",
			env["REQUEST_METHOD"],
			env["PATH_INFO"],
			env["QUERY_STRING"].empty? ? "" : "?"+env["QUERY_STRING"],
			env["HTTP_VERSION"],
			status.to_s[0..3],
			now - began_at ]
	end
end

LOGGER = ColorLogger.new

class Session

	attr_reader :save_on_server
	attr_reader :user_id
	
	def self.from_cookie(cookie)
		return self.new(cookie)
	end
	
	def initialize(cookie)
		@save_on_server = false
		@expires = Time.now + 60
		@user_id = nil;
		if cookie
			begin 
				h = Marshal.load(Base64.decode64(cookie))
				@user_id = h[:id]
			rescue
				LOGGER.error("Error decoding cookie #{cookie}")
			end
		end
	end
	
	def to_cookie_hash
		{
			:path => '/',
			:httponly => true,
			:expires => @expires,
			:value => Base64.encode64(Marshal.dump(
				{:id => @user_id}
			))
		}
	end
	
end

class SessionMiddleware
	def initialize(app, options={})
		@app = app;
		@key = "munch"
	end

	def call(env)
		load_session(env)
		status, headers, body = @app.call(env)
		save_session(env, headers)
	end
	
	def load_session(env)
		request = Rack::Request.new(env)
		session_data = request.cookies[@key]
		env["rack.session"] = Session.from_cookie(session_data)
	end
	
	def save_session(env, headers)
		if env["rack.session"].dirty
			Rack::Utils.set_cookie_header!(headers, @key, env["rack.session"].to_cookie_hash)
		end
	end
end

DataMapper::Logger.new(STDERR, :debug, "~", true)
DataObjects::Logger.new(STDERR, :debug, "~", true)

DataMapper::Model.raise_on_save_failure = true
# Use either the default Heroku database, or a local sqlite one for development
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")
DataMapper.finalize
DataMapper.auto_upgrade!


#
# Main application
#
class SvegApp < Sinatra::Base

	set :root, File.dirname(__FILE__)
	set :templates, File.join(settings.root, "templates");

#	set :logging, true - we are doing our own logging via LOGGER
	set :show_exceptions, true

	helpers do
		include Rack::Utils
		alias_method :h, :escape_html
		def flash_notice=(msg)
			@flash_notice = msg
		end

		def flash_error=(msg)
			@flash_error = msg
		end

		def show_error(object, prop)
			"<span class=\"error_message\">#{object.errors[prop]}</span>" if (object.errors[prop])
		end

	end

	#  require "sinatra/reloader" if development?

	configure(:development) do
	#   register Sinatra::Reloader
	#    also_reload "book_model.rb"
	end

	after do
		headers({"X-FlashError" => @flash_error}) if @flash_error
		headers({"X-FlashNotice" => @flash_notice}) if @flash_notice
	end

	#
	# CONTROLLER METHODS
	#

	get '/' do
		'Hello world!'
	end

	get '/editor' do
		erb :editor
	end

	get '/books/new' do
		@book = Book.new({}, {})
		erb :book_new
	end

	get '/books/:id' do
		@book = Book.get(params[:id])
		content_type :json
		@book.to_json()
	end

	post '/books' do
		begin
			Book.transaction do |t|
				@book = Book.new(params[:book], params[:template])
				@book.init_from_template
				content_type :json
				"{ \"id\" : #{@book.id} }"
			end
		rescue => ex
			LOGGER.error(ex.message)
			self.flash_error= "Errors prevented the book from being saved. Please fix them and try again."
			[400, erb(:book_new)]
		end
	end

	get '/auth/login'
		erb :login
	end
	
	post '/auth/login'
	end

# setup & run	
	use SvegLogger
	use SessionMiddleware

	run! if app_file == nil

end
