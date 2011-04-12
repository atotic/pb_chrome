require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'
require 'json'

require 'model/user'

class Book
  include DataMapper::Resource
  
  property :id,           Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
  property :title,        String,   :required => true
  property :template_attributes,   Text
  property :template_id,  String

	belongs_to :user
  has n, :pages, 'BookPage'
  
  validates_with_method :template_attributes, :method => :validate_template_attributes
  
  validates_with_method :pages, :method => :validate_pages
  
  #
  # *args are either:
  # [ {attributes}, {template_attributes}]
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
  
  def to_json(*a)
    {
      :id => self.id,
      :title => self.title,
      :pages => self.pages.to_a
    }.to_json(*a)
  end
  
  def get_template
    BookTemplate.new(JSON.parse(self.template_attributes))
  end
  
  def validate_template_attributes
    template = self.get_template
    return [false, template.error] if template.error
    true
  end
  
  def validate_pages
    self.pages.each do |page|
        return [false, "Invalid book page #{page.errors.full_messages.join(";")}"] unless page.valid?
    end
    true
  end

  def init_from_template
    self.save unless self.id  # we need to be saved before adding associated records
    t = self.get_template
    t.get_default_pages.each do |page|
      self.pages << page
    end
    self.save
  end
  
end

class BookPage
  include DataMapper::Resource
  
  property :id,           Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime

  property :html,         Text, :lazy => false
  property :width,        String
  property :height,       String
  
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
  
  def initialize(attrs)
    @style = attrs[:style] if attrs
    @style ||= "6x6"
    f = self.folder
    unless @error
      begin
         data = YAML::load_file(File.join(f, 'book.yml'))
         @width = data["width"]
         @height = data["height"]
       rescue => e
         @error = e.message
       end
     end    
  end
  
  def folder
    f = File.join(SvegApp.templates, @style)
    @error = "Book template #{@style} does not exist." unless File.exist?(f)
    f
  end
  
  def get_default_pages
    [
      PageTemplate.get(self, "cover").make_page(),
      PageTemplate.get(self, "simple").make_page()
    ]
  end

end

class PageTemplate
  
  attr_reader "error"

  # get named template
  def self.get(book_template, page_template)
    self.new(book_template, page_template)
  end
  
  def initialize(book_template, template_id)
    file_name = File.join(book_template.folder(), "pages", template_id + ".yml")
    data = YAML::load_file(file_name)
    @width = data["width"] || book_folder.width
    @height = data["height"] || book_folder.height
    @html = IO.read(File.join(book_template.folder(), "pages", template_id + ".svg"))
  end
  
  def make_page()
    BookPage.new({
      :width => @width, :height => @height, :html => @html
    })
  end

end
