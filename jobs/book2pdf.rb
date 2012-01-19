require "model/book"
require "fileutils"

module PB
	
# Create PDF file for a book
class BookToPdf
	
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
		
	def process(book_id)
		start_at = Time.now
		book = Book.get(book_id)
		raise "No such book" unless book
		# create book directories inside pdf-books
		book_dir = get_book_dir(book)
		FileUtils.rm_r(book_dir, :force => true); # clean the dir
		FileUtils.mkdir_p(book_dir)
		photo_dir = File.join(book_dir, "photos")
		FileUtils.mkdir_p(photo_dir)
		pdf_dir = File.join(book_dir, "pdf")
		FileUtils.mkdir_p(pdf_dir)
		# copy css
		FileUtils.cp(File.join(SvegSettings.templates, "print-sheet.css"), book_dir);
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

		# create a PDF for every HTML
		pdf_files = []
		LOGGER.info "Creating PDFs"
		html_files.each_index do |index|
			html_file = html_files[index]
			book_page = book.pages[index]
			pdf_name = File.join(pdf_dir, File.basename(html_file).sub(".html", ".pdf"))
			pdf_files << pdf_name
			cmd_line = self.get_cmd_export_pdf(html_file, pdf_name, book_page.width, book_page.height)
			LOGGER.info cmd_line
			success = Kernel.system cmd_line
			raise ("PDF generator crashed " + $?.to_s) unless success
		end
		# merge the pdfs
		book_pdf = File.join(book_dir, "book.pdf")
		cmd_line = self.get_cmd_merge_pdf(book_pdf, pdf_files)
		success = Kernel.system cmd_line
		raise ("PDF join crashed " + $?.to_s) unless success
		# mark it in the book
		book.pdf_location = book_pdf
		book.save!
		LOGGER.info("PDF generation took " + (Time.now - start_at).to_s)
	end
end

end
