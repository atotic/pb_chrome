require 'json'
require 'sequel'

require 'app/user'
require 'app/photo'
require 'app/book_template'
require 'app/command_stream'
require 'app/book2pdf_job'

module PB
	
class Book < Sequel::Model(:books)
	
	plugin :timestamps
	
	many_to_one :user
	one_to_many :pages, :class => 'PB::BookPage'
	many_to_many :photos
	one_to_many :chrome_pdf_tasks, :class => 'PB::ChromePDFTask'
	one_to_many :browser_commands, :class => 'PB::BrowserCommand'

	# manual removal of all associations
	def before_destroy
		# remove all dependent objects
		pages.each { |p| p.delete } # delete, not destroy, because pages update book when destroyed
		chrome_pdf_tasks.each { |t| t.destroy }
		browser_commands.each { |c| c.destroy }

		# save photo list, so we can traverse it
		p = photos.collect { |x| x }
		# destroys the association
		remove_all_photos
		# remove orphan photos
		p.each do |photo|
			# destroy photos if we are the only book
			success = true
			success = photo.destroy if photo.books.count == 0
			PB.logger.error "Could not destroy photo #{photo.id}" unless success
		end
	end
	
	def validate
		page_errors = []
		pages.each do |p|
			p.validate
			page_error.concat p.full_messages if (p.errors.count > 0)
		end
		errors.add(:pages, "Pages did not validate #{page_error.to_s}") unless page_errors.empty?
	end
	
	def to_json(*a)
		last_cmd_id = BrowserCommand.last_command_id(self.pk)
		{
			:id => self.pk,
			:title => self.title,
			:pages => self.pages.to_a,
			:photos => self.photos.to_a,
			:page_order => self.page_order.split(",").map { |x| x.to_i },
			:template_id => self.template_name,
			:last_server_cmd_id => (last_cmd_id ? last_cmd_id : 0)
		}.to_json(*a)
	end

	def pdf_path
		self.pdf_location
	end

	def insertPage(page, page_number)
		page_number ||= 0;
		self.add_page page
		page.save # id is created here
		if self.page_order
			self.page_order += ","
		else
			self.page_order = ""
		end
		self.page_order = self.page_order.split(',').insert(page_number, page.id).join(',') 
		self.save
	end
	
	def generate_pdf(force = false)
		return "Book PDF generation not started. There is already a build in progress." if self.pdf_generate_in_progress && !force
		self.pdf_location = nil
		self.pdf_generate_error = nil
		self.pdf_generate_in_progress = true
		save
		Delayed::Job.enqueue BookToPdfPrepJob.new(self.id)
		return "Book PDF proof will be ready in a few minutes."
	end
	
	def generate_pdf_done(pdf_path)
		self.pdf_location = pdf_path
		self.pdf_generate_error = nil
		self.pdf_generate_in_progress = false
		self.save
	end
	
	def generate_pdf_fail(err_msg)
		self.pdf_location = ""
		self.pdf_generate_error = err_msg[0..49]
		self.pdf_generate_in_progress = false
		begin
			self.save
		rescue => ex
			puts ex.message
			puts ex.backtrace
			puts self.errors
		end
	end

end

class BookPage < Sequel::Model(:book_pages)
	
#	property :id,					 Serial 
#	property :created_at,		DateTime
#	property :updated_at,		DateTime

#	property :html,					Text, :lazy => false
#	property :width,				String # css width units px|in|cm etc
#	property :height,				String # css width units
#	property :icon,					Text, :lazy => false # html icon
#	property :position,			String # page position (see template): cover|flap|inside|middle|back

	plugin :timestamps

	many_to_one :book
	
	def to_json(*a)
		{
			:id => self.pk,
			:width => self.width,
			:height => self.height,
			:html => self.html,
			:icon => self.icon,
			:position => self.position
		}.to_json(*a)
	end
	
	def before_destroy
		# removes page from book page order
		b = self.book
		page_order = b.page_order.split(",")
		page_order.delete(self.pk.to_s)
		b.page_order = page_order.join(',')
		b.save
	end
end

end
