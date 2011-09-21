require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'
require 'json'
require 'nokogiri'
require 'css_parser'

require 'model/user'
require 'model/photo'
require 'model/book'

module PB
# Holds information about a book template
class BookTemplate
	
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

	def get_all_pages
		Dir.entries( File.join(self.folder(), "pages"))\
			.select { |x| x.end_with?(".html") }\
			.map { |x| PageTemplate.get(self, x.gsub(/\.html$/, "")) }
	end
	
	def get_asset_path(asset_name)
		File.join(self.folder, "assets", asset_name);
	end
end

# Used when generate_icon encounters pre-existing file
class FileExistsError < IOError; end
# Used when generate_icon detects malformed HTML 
class MalformedHTML < SyntaxError; end

# Book page template, holds HTML & yaml data
class PageTemplate
	
	attr_reader "template_id"
	attr_reader "book_template"
	
	# get named template
	def self.get(book_template, page_template)
		self.new(book_template, page_template)
	end
	
	def initialize(book_template, template_id)
		@book_template = book_template
		@template_id = template_id
		data = YAML::load_file(self.yml_file_name)
		raise "Could not load yaml file #{file_name}" unless data
		@width = data["width"] 
		@height = data["height"]
		@html = IO.read(self.html_file_name)
	end
	
	def icon_file_name
		File.join(@book_template.folder(), "pages", @template_id + "_icon.html")
	end
	
	def yml_file_name
		File.join(@book_template.folder(), "pages", @template_id + ".yml")
	end
	
	def html_file_name
		File.join(@book_template.folder(), "pages", @template_id + ".html")
	end
				
	def make_page()
		BookPage.new({
			:width => @width, :height => @height, :html => @html
		})
	end
	
	# generates simple icon
	# algorithm:
	# load template page
	# generate small page based upon template
	# Template page must contain:
	# <div style="width:?px;height:?px">
	#  <div class="book-image" style="width:?px;height:?px;top:?px;left:?px">
	#   <img class="actual-image" style="
	def generate_icon()
		def get_page_info(doc)
			page_info = { :width => 0, :height => 0, :images => [] }
			# get page width/height from main div
			page_div = doc.xpath("//body/div")[0]
			raise MalformedHTML.new("Page template missing enclosing div") if page_div.nil?
			
			css_rule = CssParser::RuleSet.new("div", page_div['style'])
			raise MalformedHTML.new("Enclosing div must have width/height") unless css_rule['width'].to_i && css_rule['height'].to_i
			page_info[:width] = css_rule['width'].to_i
			page_info[:height] = css_rule['height'].to_i
	
			# get all <div class="book-image">
			page_img_tags = doc.xpath("//div[@class='book-image']")
			page_img_tags.each do |div|
				div_css_rule = CssParser::RuleSet.new("div", div['style'])
				raise MalformedHTML.new("<div class='book-image'> must have top/left/width/height defined in pixels")\
				 unless div_css_rule["top"] && div_css_rule["left"] && div_css_rule["width"] && div_css_rule["height"]
				# get css position attributes
				img_info = {}
				['top', 'left', 'width', 'height'].each do |prop|
					img_info[prop] = div_css_rule[prop].to_i
				end
				# get img src
				img_tags = div.xpath("//img[@class='actual-image']")
				if img_tags.empty? then
					img_info['src'] = img_info['height'] > img_info['width'] ? "assets/common/v1.jpg" : "assets/common/h1.jpg"
				else
					img_tag = img_tags[0]
					raise MalformedHTML.new("<img class='actual-image'> must have src attribute") unless img_tag['src']
					img_info['src'] = img_tag["src"]		
				end
				page_info[:images].push(img_info)
			end
			page_info
		end
		
		raise FileExistsError.new("File exists, will not overwrite") if File.exists?(self.icon_file_name)
		f = File.open(self.html_file_name)
		doc = Nokogiri::HTML(f)
		f.close
		
		# Step 1: parse all the information from the HTML template

		page_info = get_page_info(doc);
		
	end
end

end