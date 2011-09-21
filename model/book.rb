require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'
require 'json'

require 'model/user'
require 'model/photo'
require 'model/book_template'

module PB
	
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
			:page_order => self.page_order.split(",").map { |x| x.to_i }
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

end
