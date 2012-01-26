require "app/book"
require "fileutils"

# PDF Generation is fully documented here, and implemented in many pieces
#
# Architecture discussion:
# PDF generation uses Chrome. Chrome has the best HTML=>PDF engine.
# Chrome is not built to be run as a command-line tool, and 
# coaxing it into spitting out PDFs on demand involves a
# VERY CONVOLUTED DATA FLOW.
#
# This is how it is done:
#
# New applications implemented:
# A) pageCapture.saveAsPDF: patch Chrome to add pageCapture.saveAsPDF js API
# B) pdf_saver_extension Chrome extension: implement a new Chrome extension. 
#    pdf_saver_extension polls pdf_saver_server for work, when it gets some converts page to HTML, and sends it
# C) pdf_saver_server: Rack server that saves incoming PDFs into a database
# 
# Integrating these applications into Sveg
# 
# 3 servers: sveg, delayed_job, pdf_saver_server, and a Chrome instance work together
# 
# sveg gets the request: post '/books/:id/pdf', passes it on to
# Book.generate_pdf creates a delayed_job.
# delayed_job (if executed), will call Book.generate_pdf_done|fail
# delayed_job is BookToPDF.perform. It creates html files,  then open html in Chrome.
# 
# chrome gets 
# PDFSaver Chrome extension converts html to pdf, and sends pdf to pdf_saver_server
# pdf_saver_server
# BookToPDF.perform creates local html files to be converted.
# Then it opens local html files
# The cost of using Chrome is a convoluted data flow, that happens because
# Chrome PDF engine is not exposed by any Chrome API by default.
# We patch Chrome and implement pageCapture.saveAsPDF js API.
# pageCapture.saveAsPDF allows Chrome extensions to convert pages to from HTML => PDF. PDF comes back as a blob.
# Chrome extensions cannot directly communicate with host OS. 
# 
# 

module PB

class ChromeHTMLToPDFTask
  include DataMapper::Resource
  property :id,					 Serial
  
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	property :html_file,    String
	property :pdf_file,     String
	property :book_id,      Integer
	property :local_url,    String
	
	STAGE_INITIAL = 0
	STAGE_CHROME = 1
	STAGE_DONE = 2
	property :processing_stage, Integer, :default =>  STAGE_INITIAL # processing stage

	property :has_error,        Boolean, :default => false
	property :error_message,    String
end

# Create PDF file for a book
class BookToPdf
	
	def initialize(book_id)
	  @book_id = book_id
  end
  
	def get_book_dir(book)
		dir = File.join(SvegSettings.book2pdf_dir, book.user_id.to_s)
		FileUtils.mkdir_p(dir)
		dir
	end
	
	# Fix image links src="/photo/1?size=display" => src="photos/1.ext"
	def fix_html(html)
		split = html.split /(<img[^>]*>)/im
		split.each_index do |i|
			# split image into components
			match = split[i].match( /(<img[^>]*)(src=")(\/photo\/)(\d+)([^"]*)(.*)/ )
			if match
				front, href, photo, image_id, size, back = match[1], match[2], match[3], match[4], match[5], match[6]
				photo = "./photos/"
				image_id = image_id + File.extname(Photo.get(image_id).storage)
				split[i] = front + href + photo + image_id + back
			end
		end
		split.join
	end
	
	# converts css units to pixels ex: 6in => 432 
	def convertToPixels(val)
		return val.to_i unless val =~ /^(\d+)\s*(\w+)$/i
		pixelConversion = {
			"in" => 72,
			"cm" => 28.35,
			"mm" => 2.835,
			"px" => 1,
			"pt" => 1,
			"pc" => 6
		}
		if pixelConversion.has_key? $~[2].downcase
			val = pixelConversion[ $~[2].downcase ] * $~[1].to_f;
		else
			raise "Could not convert #{val}. Unknown unit"
		end
		val.to_i
	end
	
	def get_cmd_export_pdf(html_file, pdf_file, width, height)
# wkpdf -p custom:700x700  -m 0 0 0 0 --paginate false --source page1.html --output page1.pdf
		width = convertToPixels(width)
		height = convertToPixels(height)
		cmd_line = "/usr/bin/wkpdf"
		cmd_line << " --paper custom:#{width}x#{height}"
		cmd_line << " --margins 0 0 0 0"
		cmd_line << " --paginate false"
		cmd_line << " --print-background"
		cmd_line << " --source #{html_file}"
		cmd_line << " --output #{pdf_file}"
		cmd_line
	end
	
	def get_cmd_merge_pdf(book_pdf, pdf_files)
		cmd_line = "/System/Library/Automator/Combine\\ PDF\\ Pages.action/Contents/Resources/join.py "
		cmd_line << "-o #{book_pdf} "
		pdf_files.each do |pdf|
			cmd_line << pdf << " "
		end		
		cmd_line
	end
	
	def prepare_directories(book)
		book_dir = get_book_dir(book)
		FileUtils.rm_r(book_dir, :force => true); # clean the dir
		FileUtils.mkdir_p(book_dir)
		photo_dir = File.join(book_dir, "photos")
		FileUtils.mkdir_p(photo_dir)
		pdf_dir = File.join(book_dir, "pdf")
		FileUtils.mkdir_p(pdf_dir)
		return [book_dir, photo_dir, pdf_dir]	  
  end
  
  def prepare_html_files(book, book_dir)
		# copy css
		FileUtils.cp(File.join(SvegSettings.book_templates_dir, "print-sheet.css"), book_dir);
		# copy the images
		book.photos.each do |photo| 
			FileUtils.cp(photo.file_path(), photo_dir)
		end
		# create the html files
		i = 0
		index = "<html><head><title>#{book.title}</title></head><body>"
		html_files = []
		page_header = <<-eos
<html>
<head>
	<link href='print-sheet.css' rel='stylesheet' type='text/css' />
</head>
<body>
eos
		book.pages.each do |page|
			i += 1
			name = "page" + i.to_s + ".html"
			html = page.html
			f = File.new(File.join(book_dir, name), "w")
			# fix the html links
			html = self.fix_html(page.html)		
			f.print page_header, html, "</body>"
			f.close()
			index << "<li><a href='#{name}'>#{name}</a>"
			html_files << f.path
		end

		# generate index.html just for fun
		f = File.new(File.join(book_dir,"index.html"), "w")
		f.print index, "</body>"
		f.close()
    html_files
  end
  
  def create_pdf_files(book, html_files, pdf_dir)
		@logger.info "Creating PDFs"

    pdf_files = []
 		html_files.each_index do |index|
 		  task = ChromeHTMLToPDFTask.create( {
 		    :html_file => html_files[index],
  			:pdf_file => File.join(pdf_dir, File.basename(html_file).sub(".html", ".pdf")),
  			:book_id => book.id,
  			:local_url => "file:///" + File.absolute_path(html_files[index])
 		  })
 		  
      begin
        Timeout.timeout(10) do
            # ...
        end
      rescue Timeout::Error => e
          # the task took longer than 10 seconds
      end
 		  cmd_line = self.get_cmd_chrome_pdf()
			pdf_files << task.pdf_file
			cmd_line = self.get_cmd_export_pdf(html_file, pdf_name, book_page.width, book_page.height)
			@logger.info cmd_line
			success = Kernel.system cmd_line
			raise ("PDF generator crashed " + $?.to_s) unless success
		end
   
    pdf_files

  end
  
  # delayed_job callback. Creates the PDFs
	def perform()
	  begin
  	  @logger = Delayed::Worker.logger
  	  @logger.info("Book2Pdf running");
  		start_time = Time.now
  		book = Book.get(@book_id)
  		raise "No such book" unless book
  		# create book directories inside pdf-books
  		book_dir, photo_dir, pdf_dir = prepare_directories(book)
  		html_files = prepare_html_files(book, book_dir)
      pdf_files = create_pdf_files(book, html_files, pdf_dir)
    
  		# merge the pdfs
  		book_pdf = File.join(book_dir, "book.pdf")
  		cmd_line = self.get_cmd_merge_pdf(book_pdf, pdf_files)
  		success = Kernel.system cmd_line
  		raise ("PDF join crashed " + $?.to_s) unless success
  		# mark it in the book
  		book.pdf_location = book_pdf
  		book.save!
  		@logger.info("PDF generation took " + (Time.now - start_time).to_s)
  	rescue => ex
	  end
	end
end

end
