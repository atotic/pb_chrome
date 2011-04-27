require "model/book"
require "fileutils"

class BookToPdf
	
	def get_book_dir(book)
		dir = File.join(SvegApp.book2pdf_dir, book.user_id.to_s)
		FileUtils.mkdir_p(dir)
		dir
	end
	
	# Fix image links
	# Fix any other bugs in html exports
	def fix_html(html)
		# fix xlink namespace
		html = html.sub( / xlink="http:\/\/www.w3.org\/1999\/xlink"/, " xmlns:xlink=\"http://www.w3.org/1999/xlink\"" )
		# close image tags, and fix image links
		split = html.split /(<image[^>]*>)/im
		split.each_index do |i|
			# split image into components
			match = split[i].match( /(<image[^>]*)(xlink:href=")(\/photo\/)(\d+)([^"]*)(.*)/ )
			if match
				front, href, photo, image_id, size, back = match[1], match[2], match[3], match[4], match[5], match[6]
				photo = "./photos/"
				image_id = image_id + File.extname(Photo.get(image_id).storage)
				split[i] = front + href + photo + image_id + back
			end
		end
		split.join
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
		# copy the images
		book.photos.each do |photo| 
			FileUtils.cp(photo.file_path(), photo_dir)
		end
		# create the html files
		i = 0
		index = ""
		svg_files = []
		book.pages.each do |page|
			i += 1
			name = "page" + i.to_s + ".svg"
			html = page.html
			f = File.new(File.join(book_dir, name), "w")
			# fix the html links
			html = self.fix_html(page.html)		
			f.print html
			f.close()
			index << "<li><a href='#{name}'>#{name}</a>"
			svg_files << f.path
		end
		# generate index.html just for fun
		header = "<html><head><title>#{book.title}</title></head><body>"
		footer = "</body>"
		f = File.new(File.join(book_dir,"index.html"), "w")
		f.print header, index, footer
		f.close()
		# create a PDF for every SVG
		pdf_files = []
		LOGGER.info "Creating PDFs"
		svg_files.each do |svg_file|
# /Applications/Inkscape.app/Contents/Resources/bin/inkscape --export-ignore-filters -A page1.pdf page1.svg
			pdf_name = File.join(pdf_dir, File.basename(svg_file).sub(".svg", ".pdf"))
			pdf_files << pdf_name
			cmd_line = '/Applications/Inkscape.app/Contents/Resources/bin/inkscape '
			cmd_line << '--export-ignore-filters '
			cmd_line << "-A #{pdf_name} "
			cmd_line << svg_file
			success = Kernel.system cmd_line
			raise ("PDF generator crashed " + $?.to_s) unless success
		end
		# merge the pdfs
		book_pdf = File.join(book_dir, "book.pdf")
		cmd_line = "/System/Library/Automator/Combine\\ PDF\\ Pages.action/Contents/Resources/join.py "
		cmd_line << "-o #{book_pdf} "
		pdf_files.each do |pdf|
			cmd_line << pdf << " "
		end
		success = Kernel.system cmd_line
		raise ("PDF join crashed " + $?.to_s) unless success
		# save in pdf location
		book.pdf_location = book_pdf
		book.save!
		LOGGER.info("PDF generation took " + (Time.now - start_at).to_s)
	end
end