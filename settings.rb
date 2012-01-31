# Common settings, used by all sveg servers and scripts

# gem requires
require 'rubygems'
require "bundler/setup"
require 'dm-core'
require 'dm-validations'
require 'dm-migrations'
require 'dm-transactions'
require 'data_objects'


DataMapper::Property::String.length(128) # must be declared before model definition

# server code
require 'app/book'
require 'app/user'
require 'app/photo'
require 'app/book_template'
require 'app/command_stream'
require 'app/book2pdf_job'

ENV['RACK_ENV'] = 'test' if ENV.has_key? 'TEST'
ENV['RACK_ENV'] = 'development' unless ENV.has_key? 'RACK_ENV'
ENV['RAILS_ENV'] = ENV['RACK_ENV']

class SvegSettings
  
  @root_dir = File.dirname(File.expand_path(__FILE__))
  @environment = ( ENV['RACK_ENV'] || :development ).to_sym # :production :development :test
  @book_templates_dir = File.join(@root_dir, "book-templates")

  @data_dir = @environment == :test ? File.join(@root_dir, "test", "data") : File.join(@root_dir, "data")
  @tmp_dir = File.join(@data_dir, "tmp")
  @log_dir = File.join(@data_dir, "log")

  @photo_dir = File.join(@data_dir, "photo-storage") # photo storage directory
	@book2pdf_dir = File.join(@data_dir, "pdf-books") # generated books
	
	@chrome_binary = "/Users/atotic/chromium/src/out/Debug/Chromium.app/Contents/MacOS/Chromium"
	@chrome_dir = "/Users/atotic/chromium/src/out/Debug/Chromium.app"
	@chrome_profile_dir = File.join(@root_dir, "pdf_saver_chrome_profile")
	@pdf_toolkit_binary = "/usr/local/bin/pdftk"
	
  class << self
    attr_accessor :root_dir,:data_dir, :tmp_dir, :log_dir
    attr_accessor :environment
    attr_accessor :book_templates_dir, :photo_dir, :book2pdf_dir
    attr_accessor :chrome_binary, :chrome_dir, :chrome_profile_dir, :pdf_toolkit_binary
  end
  
  def self.init()
  	Dir.mkdir(@data_dir) unless File.exists?(@data_dir)
  	Dir.mkdir(@tmp_dir) unless File.exist?(@tmp_dir)
  	Dir.mkdir(@log_dir) unless File.exists?(@log_dir)
  	Dir.mkdir(@photo_dir) unless File.exists?(@photo_dir)
  	Dir.mkdir(@book2pdf_dir) unless File.exists?(@book2pdf_dir)

    # DataMapper Initialization
  	DataMapper::Model.raise_on_save_failure = true
  	database_url ="sqlite3://#{@data_dir}/#{@environment}.sqlite"
  	DataMapper.setup(:default, database_url)
  	DataMapper.finalize
    DataMapper.auto_migrate! if @environment.eql? :test
  	DataMapper.auto_upgrade! # extends tables to match model
  	Delayed::Worker.destroy_failed_jobs = false
  	Delayed::Worker.backend.auto_upgrade!
  end
end



# delayed_job initialization
# it depends on rails globals, we fake Rails object
class Rails 
  @root = SvegSettings.data_dir
  require 'log4r'
  @logger = Log4r::Logger.new 'rails_logger'
  class << self
    attr_accessor :root, :logger
  end
end
Object.const_set "RAILS_DEFAULT_LOGGER", Rails.logger
require 'delayed_job'
require 'delayed_job_data_mapper'


SvegSettings.init()

