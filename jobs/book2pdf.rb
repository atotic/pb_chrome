require "model/book"
require "fileutils"

class BookToPdf
	
	def get_book_dir(book)
		dir = File.join(SvegApp.book2pdf_dir, book.user_id.to_s)
		FileUtils.mkdir_p(dir)
		dir
	end
	
	def fix_html(html)
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
		book = Book.get(book_id)
		raise "No such book" unless book
		# create book directories inside pdf-books
		book_dir = get_book_dir(book)
		FileUtils.rm_r(book_dir, :force => true); # clean the dir
		FileUtils.mkdir_p(book_dir)
		photo_dir = File.join(book_dir, "photos")
		FileUtils.mkdir_p(photo_dir)
		# copy the images
		book.photos.each do |photo| 
			FileUtils.cp(photo.file_path(), photo_dir)
		end
		# create the html files
		header = "<html><head></head><body>"
		footer = "</body>"
		i = 0
		index = ""
		book.pages.each do |page|
			i += 1
			name = "page" + i.to_s + ".html"
			html = header + page.html + footer
			f = File.new(File.join(book_dir, name), "w")
			# fix the html links
			html = self.fix_html page.html		
			f.print header, html, footer
			f.close()
			index << "<li><a href='#{name}'>#{name}</a>"
		end
		f = File.new(File.join(book_dir,"index.html"), "w")
		f.print header, index, footer
		f.close()
		# run book to pdf
		
	end
end