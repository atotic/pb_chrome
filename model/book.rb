require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'
require 'json'

require 'model/user'
require 'model/photo'

class Book
	include DataMapper::Resource
	
	property :id,					 Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	property :title,				String,	 :required => true
	property :template_attributes,	 Text
	property :template_id,	String
	property :pdf_location,	String
	property :page_order, String	# comma separated list of page ids.
	
	belongs_to :user
	has n, :pages, 'BookPage'
	has n, :photos, :through => Resource
	
	validates_with_method :template_attributes, :method => :validate_template_attributes
	
	validates_with_method :pages, :method => :validate_pages
	
	#
	# *args are either:
	# [ user, {attributes}, {template_attributes}]
	# or [] for default book
	def initialize(*args)
		case
		when args.length == 0
			super({})
		when args.length == 3
			super(args[1])
			self.user = args[0]
			self.template_attributes = args[2].to_json
		end
	end
	
	# manual removal of all associations
	before :destroy do |book|
		book.pages.each do | page|
			page.destroy
		end
		book.photos.each do |photo|
			# destroy photos if we are the only book
			photo.destroy if photo.books.count == 1
		end
		book.book_photos.each do |bp|
			bp.destroy
		end
	end
	
	def to_json(*a)
		{
			:id => self.id,
			:title => self.title,
			:pages => self.pages.to_a,
			:photos => self.photos.to_a,
			:page_order => self.page_order.split(",").map(|x| x.to_i)
		}.to_json(*a)
	end
	
	def get_template
		BookTemplate.new(JSON.parse(self.template_attributes))
	end
	
	def validate_template_attributes
		begin
			template = self.get_template
		rescue => e
			return [false, e.message]
		end
		true
	end
	
	def validate_pages
		self.pages.each do |page|
				return [false, "Invalid book page #{page.errors.full_messages.join(";")}"] unless page.valid?
		end
		true
	end

	def init_from_template
		self.save unless self.id	# must be saved before adding associated records
		t = self.get_template
		t.get_default_pages.each do |page|
			self.pages << page
			page.save # id is created here
			if self.page_order
				self.page_order += ","
			else
				self.page_order = ""
			end
			self.page_order += page.id.to_s
		end
		self.save
	end
	
	def pdf_path
		self.pdf_location
	end

end

class BookPage
	include DataMapper::Resource
	
	property :id,					 Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime

	property :html,				 Text, :lazy => false
	property :width,				String
	property :height,			 String
	
	belongs_to :book
	
	def to_json(*a)
		{
			:id => self.id,
			:width => self.width,
			:height => self.height,
			:html => self.html
		}.to_json(*a)
	end
end
 
# Holds information about a book template
class BookTemplate
	
	attr_reader "error"
	attr_reader "width"
	attr_reader "height"

	def self.get(style) 
		return BookTemplate.new({ "style" => style });
	end
	
	def initialize(attrs)
		@style = attrs["style"] if attrs
		f = self.folder
		begin
			data = YAML::load_file(File.join(f, 'book.yml'))
			@width = data["width"]
			@height = data["height"]
			@initialPages = data["initialPages"].split(',').collect! { |s| s.strip }
		rescue => e
			raise "Error reading template book.yml file:" + e.message
		end
	end
	
	def folder
		f = File.join(SvegApp.templates, @style)
		raise "Book template #{@style} does not exist." unless File.exist?(f)
		f
	end
	
	def get_default_pages
		@initialPages.collect { |name| PageTemplate.get(self, name).make_page() }
	end

	def get_asset_path(asset_name)
		File.join(self.folder, "assets", asset_name);
	end
end

# Book page template, holds HTML & yaml data
class PageTemplate
	
	attr_reader "error"

	# get named template
	def self.get(book_template, page_template)
		self.new(book_template, page_template)
	end
	
	def initialize(book_template, template_id)
		file_name = File.join(book_template.folder(), "pages", template_id + ".yml")
		data = YAML::load_file(file_name)
		raise "Could not load yaml file #{file_name}" unless data
		@width = data["width"] || book_folder.width
		@height = data["height"] || book_folder.height
		@html = IO.read(File.join(book_template.folder(), "pages", template_id + ".html"))
	end
	
	def make_page()
		BookPage.new({
			:width => @width, :height => @height, :html => @html
		})
	end

end
