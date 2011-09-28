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
	
	attr_reader :width
	attr_reader :height
	attr_reader :folder
	attr_reader :style
	
	def self.get(style) 
		return BookTemplate.new({ "style" => style });
	end
	
	def self.all()
		Dir.entries(SvegApp.templates)\
			.select { |x| !x.start_with?(".") && File.directory?(File.join(SvegApp.templates, x)) }\
			.map { |x| BookTemplate.get(x) }
	end
	
	def initialize(attrs)
		@style = attrs["style"] if attrs
		@folder = File.join(SvegApp.templates, @style)
		raise "Book template #{@style} does not exist." unless File.exist?(@folder)
		begin
			data = YAML::load_file(self.yml_file_name)
			@width = data["width"]
			@height = data["height"]
			@initialPages = data["initialPages"].split(',').collect! { |s| s.strip }
		rescue => e
			raise "Error reading template book.yml file:" + e.message
		end
	end
		
	def pages_folder_name
		File.join(@folder, "pages")
	end
	
	def assets_folder_name
		File.join(@folder, "assets")
	end
	
	def yml_file_name
		File.join(@folder, 'book.yml')	
	end
	
	def get_default_pages
		@initialPages.collect { |name| PageTemplate.get(self, name).make_page() }
	end

	def get_all_pages
		Dir.entries(SvegApp.templates)\
			.select { |x| x.end_with?(".html") && !x.end_with?("_icon.html") }\
			.map { |x| PageTemplate.get(self, x.gsub(/\.html$/, "")) }
	end
	
	# m[1] filename, m[2] ext
	@@IMAGE_MATCH = /(.*)\.(jpg|png|gif|JPG|PNG|GIF)\Z/ 
	# m[1] filename,m[2] display|icon, m[3] ext
	@@DISPLAY_ICON_IMAGE_MATCH = /(.*)_(display|icon)\.(\w+)\Z/ #
	
	def get_asset_path(asset_name, size = nil)
		unless size.nil?
			m = @@IMAGE_MATCH.match(asset_name)
			asset_name = m[1] + "_" + size + "." + m[2]
		end
		File.join(self.folder, "assets", asset_name);
	end
	
	# array of asset file names
	def get_image_assets
		images = Dir.entries( self.assets_folder_name )\
			.select { |x| ( x =~ @@IMAGE_MATCH) != nil }\
			.select { |x| ( x =~ @@DISPLAY_ICON_IMAGE_MATCH ) == nil }
		images
	end
	
	# creates resized versions (_display & _icon) of assets
	def multisize_image_assets
		self.get_image_assets.each do |img| 
			m = @@IMAGE_MATCH.match(img)
			old_file_name = File.join(self.assets_folder_name, img)
			new_file_name = File.join(self.assets_folder_name, m[1] + "_display." + m[2])
			unless File.exists?(new_file_name)
				cmd_line = PhotoStorage.get_cmd_resize(1024, old_file_name, new_file_name)
				success = Kernel.system cmd_line
				raise ("Multisize image resize #{img} failed" + $?.to_s) unless success
			end
			new_file_name = File.join(self.assets_folder_name, m[1] + "_icon." + m[2])
			unless File.exists?(new_file_name)
					cmd_line = PhotoStorage.get_cmd_resize(128, old_file_name, new_file_name)
					success = Kernel.system cmd_line
					raise ("Multisize image resize #{img} failed" + $?.to_s) unless success
			end
		end
	end
	
	def clean_image_assets
		images = Dir.entries( self.assets_folder_name )\
			.select { |x| ( x =~ @@IMAGE_MATCH ) != nil }\
			.select { |x| ( x =~ @@DISPLAY_ICON_IMAGE_MATCH ) != nil }
		images.each do |img|
			file_name = File.join(self.assets_folder_name, img)
			File.delete(file_name) if File.exists?(file_name)
		end
	end
end

# Used when generate_icon encounters pre-existing file
class FileExistsError < Exception; end
# Used when generate_icon detects malformed HTML 
class MalformedHTML < Exception; end

# Book page template, holds HTML & yaml data
class PageTemplate
	
	attr_reader :template_id
	attr_reader :book_template
	attr_reader :icon
	
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
		@icon = File.exists?(self.icon_file_name) ? IO.read(self.icon_file_name) :\
		 "<div class='page-icon' style='width:128px;height:128px'><p>Default icon</p></div>"
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
				
	def make_page
		doc = Nokogiri::HTML(@html)
		# generate unique id's for all image/text nodes, and any other nodes that have an id
		id_nodes = doc.xpath("//body/*[@id]")
		['book-image', 'actual-image', 'book-text', 'actual-text'].each do |classname|
			id_nodes = id_nodes | doc.xpath("//*[@class='#{classname}']")
		end
		id_nodes.each do |id_node|
			id_node['id'] = rand(36**5).to_s(36) + (id_node['id']	|| "") # 5 character random id generation. Thanks, stackoverflow
		end
		html_with_id = doc.xpath("//body/div")[0].serialize(:save_with => Nokogiri::XML::Node::SaveOptions::NO_DECLARATION)
		# select every element that has an id
		# randomly change the id
		# save the new html
		BookPage.new({
			:width => @width, :height => @height, :html => html_with_id, :icon => @icon
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
	def generate_icon_file()
		
		# Step 1: parse all the information from the HTML template
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
				['top', 'left', 'width', 'height'].each { |prop| img_info[prop] = div_css_rule[prop].to_i }
				# get img src
				img_tags = div.xpath("//img[@class='actual-image']")
				if img_tags.empty? then
					img_info['src'] = img_info['height'] > img_info['width'] ? "/assets/common/v1.jpg" : "/assets/common/h1.jpg"
				else
					img_tag = img_tags[0]
					raise MalformedHTML.new("<img class='actual-image'> must have src attribute") unless img_tag['src']
					img_info['src'] = img_tag["src"]		
				end
				page_info[:images].push(img_info)
			end
			page_info
		end
		
		# Step 2: generate the HTML
		# <div class="page-icon" style="width:??px;height:128px">
		#   <img data-img-pos="X" src="url?size=icon" 
		#	    style="position:relative;top:X%;left:X%,width:X%;height:X%">
		def make_icon_html(page_info)
			div_style = {
				:width => 128,
				:height => 128 * page_info[:width] / page_info[:height]
			}
			image_data = []
			page_info[:images].each_index do |i|
				img = page_info[:images][i]
				img_style = {
					:top => (img["top"].to_f / page_info[:height] * 100).to_i,
					:left => (img["left"].to_f / page_info[:width] * 100).to_i,
					:height => (img["height"].to_f / page_info[:height] * 100).to_i,
					:width => (img["width"].to_f / page_info[:width] * 100).to_i,
					:img_pos => i,
					:src => img["src"].sub(/\\?size=[a-zA-Z]+$/, "") + "?size=icon"
				}
				image_data.push(img_style);
			end
			html = StringIO.new
			html << "<div class='page-icon'"
			html << " style='width:#{div_style[:width]}px;height:#{div_style[:height]}px'>"
			image_data.each do |img|
				html << "\n<img data-img-pos='#{img[:img_pos]}'"
				html << " src='#{img[:src]}'"
				html << " style='width:#{img[:width]}%;height:#{img[:height]}%;top:#{img[:top]}%;left:#{img[:left]}%'"
				html << ">"
			end
			html << "\n</div>"
			html.string
		end
		
		raise FileExistsError.new("File exists, will not overwrite") if File.exists?(self.icon_file_name)
		f = File.open(self.html_file_name)
		doc = Nokogiri::HTML(f)
		f.close
		
		page_info = get_page_info(doc);
	
		html = make_icon_html(page_info);

		File.open(self.icon_file_name, 'w') { |f| f.write(html) }
		
		# update image count in YAML
		data = YAML::load_file(self.yml_file_name)
		data["image_count"] = page_info[:images].length
		File.open(self.yml_file_name, "w") { |f| f.write(YAML::dump(data)) }
		
	end
	
	def delete_icon_file
		File.delete(self.icon_file_name) if File.exists?(self.icon_file_name)	
	end
	
end

end