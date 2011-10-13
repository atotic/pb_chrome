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
	property :pdf_location,	String
	property :page_order, String	# comma separated list of page ids.
	property :template_name, String # name of the template
	property :template,	 Text	# template attributes, stored as json
	
	belongs_to :user
	has n, :pages, 'BookPage'
	has n, :photos, :through => Resource
		
	validates_with_method :pages, :method => :validate_pages
	
	#
	# *args are either:
	# [ user, {attributes}]
	# or [] for default book
	def initialize(*args)
		case
		when args.length == 0
			super({})
		when args.length == 2
			super(args[1])
			self.user = args[0]
		else
			raise "Book must have a user"
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
	
	# template is set as a hash, but retreived as an array
	def template=(new_template)
		self.template_name = new_template["name"]
		new_template = new_template.to_json unless template.is_a? String
		super(new_template)
	end
	
	def to_json(*a)
		{
			:id => self.id,
			:title => self.title,
			:pages => self.pages.to_a,
			:photos => self.photos.to_a,
			:page_order => self.page_order.split(",").map { |x| x.to_i },
			:template_id => self.template_name
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
	
	def pdf_path
		self.pdf_location
	end

end

class BookPage
	include DataMapper::Resource
	
	property :id,					 Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime

	property :html,					Text, :lazy => false
	property :width,				String # css width units px|in|cm etc
	property :height,				String # css width units
	property :icon,					Text, :lazy => false # html icon
	property :position,			String # page position (see template): cover|flap|inside|middle|back

	belongs_to :book
	
	def to_json(*a)
		{
			:id => self.id,
			:width => self.width,
			:height => self.height,
			:html => self.html,
			:icon => self.icon,
			:position => self.position
		}.to_json(*a)
	end
end

end
