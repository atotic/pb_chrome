require 'rubygems'
require 'sinatra/base'
require 'erb'

require 'logger'
require 'json'

require 'dm-validations'
require 'dm-core'
require 'dm-migrations'

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

DataMapper.finalize
DataMapper::Logger.new(STDOUT, :debug)
DataMapper::Model.raise_on_save_failure = true
# Use either the default Heroku database, or a local sqlite one for development 
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite::memory:")
DataMapper.auto_upgrade!

class BookApp < Sinatra::Base
 
  set :logger, ColorLogger.new
  set :logging, true
  set :root, File.dirname(__FILE__)
  set :templates, File.join(settings.root, "templates");


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
    @book = Book.new
    erb :book_new
  end

  get '/books/:id' do
    debugger
    @book = Book.get(params[:id])
    content_type :json
    @book.to_json()
  end
  
  post '/books' do
    @template = BookTemplate.new(params[:template])
    @book = Book.new(params[:book])
    @template.initialize_book(@book)
    if @book.valid? && @book.save
      self.flash_notice= "Book successfully created."
      content_type :json
      "{ \"id\" : #{@book.id} }"
    else
      self.flash_error= "Book was not created"
      [400, erb(:book_new)]
    end
  end
  
  require "sinatra/reloader" if development?
  run! if app_file == nil

end
