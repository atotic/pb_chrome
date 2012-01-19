# Common settings, used by delayed_job, sveg, Rakefile

# gem requires
require 'rubygems'
require "bundler/setup"
require 'dm-core'
require 'dm-validations'
require 'dm-migrations'
require 'dm-transactions'
require 'data_objects'


# server code
require 'model/book'
require 'model/user'
require 'model/photo'
require 'model/book_template'
require 'model/command_stream'

ENV['RACK_ENV'] = 'development' unless ENV.has_key?('RACK_ENV')
ENV['RAILS_ENV'] = ENV['RACK_ENV']

class SvegSettings
  
  @root_dir = File.dirname(File.expand_path(__FILE__))
  @tmp_dir = File.join(@root_dir, "/tmp")
  @environment = ( ENV['RACK_ENV'] || :development ).to_sym
  @book_templates = File.join(@root_dir, "book-templates")

  @disk_storage = @environment == :test ? File.join(@root_dir, "test") : @root_dir
  @photo_dir = File.join(@disk_storage, "photo-storage") # photo storage directory
	@book2pdf_dir = File.join(@disk_storage, "pdf-books") # generated books
	
  class << self
    attr_accessor :root_dir, :tmp_dir, :book_templates, :photo_dir, :book2pdf_dir
  end

  
  def self.init()
  	Dir.mkdir(@tmp_dir) unless File.exist?(@tmp_dir)
    # DataMapper Initialization
    #DataMapper.auto_migrate!  # blows up database
  	DataMapper::Model.raise_on_save_failure = true
  	database_url ="sqlite3://#{@root_dir}/#{@environment}.sqlite"
  	database_url = "sqlite3://#{@disk_storage}/test.sqlite" if @environment == :test
  	DataMapper.setup(:default, database_url)
  	DataMapper.finalize
  	DataMapper.auto_upgrade! # extends tables to match model
  	Delayed::Worker.backend.auto_upgrade!
  end
end

# delayed_job accesses rails globals, we fake Rails
require 'logger'
class Rails 
  @root = SvegSettings.root_dir
  @logger = Logger.new(STDERR)
  class << self
    attr_accessor :root, :logger
  end
end
Object.const_set "RAILS_DEFAULT_LOGGER", Rails.logger
require 'delayed_job'
require 'delayed_job_data_mapper'

SvegSettings.init()

