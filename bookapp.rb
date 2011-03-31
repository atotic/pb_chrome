require 'rubygems'
require 'sinatra/base'
require 'erb'
require 'logger'
require 'json'
require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-transactions'
require 'data_objects'
require 'book_model'
require 'ruby-debug'

STDERR.write "hello err"
STDOUT.write "hello out"

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

class BookAppLogger
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

DataMapper::Logger.new(STDERR, :debug, "~", true)
DataObjects::Logger.new(STDERR, :debug, "~", true)

DataMapper::Model.raise_on_save_failure = true
# Use either the default Heroku database, or a local sqlite one for development
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")
DataMapper.finalize
DataMapper.auto_upgrade!
# hack to try to keep our database from disappearing
# Book.repository().adapter().send(:open_connection)

class BookApp < Sinatra::Base

	set :root, File.dirname(__FILE__)
	set :templates, File.join(settings.root, "templates");

#	set :logging, true
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

	use BookAppLogger
	run! if app_file == nil

end
