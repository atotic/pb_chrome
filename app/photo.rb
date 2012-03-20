require 'sequel'
require 'app/book'
require 'fileutils'
require 'digest/md5'

module PB
#
# Photo represents photos in our system
#
class Photo < Sequel::Model(:photos)
		
#	property :display_name,	String
#	property :storage,			String # where is the image stored locally
#	property :md5,					String # md5 hash

	plugin :timestamps
	
	many_to_one :user
	many_to_many :books
	
	DISPLAY_SIZE = 1024
	ICON_SIZE = 256

	def to_json(*a)
		{
			:id => self.id,
			:display_name => self.display_name,
			:md5 => self.md5
		}.to_json(*a)
	end

	def file_path(*size_arg) # call with no args for full size, or specify size as 'icon'|'display'
		size = size_arg.length > 0 ? size_arg[0] : "";
		size = size.to_s
		# transform filename.jpg to filename_size.jpg
		name_arry = self.storage.rpartition(File.extname(self.storage)) # [ "file", ".jpg", ""]
		name_arry.insert(1, "_icon") if size.eql? 'icon'
		name_arry.insert(1, "_display") if size.eql? 'display'
		File.join( PhotoStorage.get_user_dir(self), name_arry.join )
	end
	
	def url()
		"/photo/" + self.id.to_s
	end
	
	def before_destroy
		PB.logger.info("destroying photo #{self.pk}#{self.display_name}")
		PhotoStorage.destroyFile self
	end
end

# Photos are stored inside SvegSettings.photo_dir/:user_id/:photo_id.img
# 
class PhotoStorage
	# stores the uploaded file, and updates
	
	def self.get_user_dir(photo)
		dir = File.join(SvegSettings.photo_dir, photo.user_id.to_s)
		FileUtils.mkdir_p(dir)
		dir
	end
	
	def self.auto_orient(photo)
		path = File.expand_path(photo.file_path)
		# ImageMagick takes 1.3s to start up, so we query with gm to see if rotation is necessary
		cmd_query = "#{SvegSettings.graphicsmagick_binary} identify \"#{path}\" -format \"%[EXIF:Orientation]\""
		result  = `#{cmd_query}`.chomp
		raise ("Could not query orientation " + $?.to_s) unless $? == 0
		return if (result.eql?("unknown") || result.eql?("1")) # photo property oriented
		LOGGER.info("auto-orienting image")
		cmd_line = "#{SvegSettings.convert_binary} \"#{path}\"  \"#{path}\""
		success = Kernel.system cmd_line
		raise("Photo orient failed" + $?.to_s) unless success
	end

	def self.resize(photo)
		src = File.expand_path(photo.file_path)
		dest_icon = File.expand_path(photo.file_path('icon'))
		dest_display = File.expand_path(photo.file_path('display'))
		cmd_line = "#{SvegSettings.graphicsmagick_binary} convert"
		# read in file, remove exif data
		cmd_line += " -size #{Photo::DISPLAY_SIZE}X#{Photo::DISPLAY_SIZE} #{src} +profile \"*\""
		# convert display, write it out
		cmd_line += " -geometry \"#{Photo::DISPLAY_SIZE}X#{Photo::DISPLAY_SIZE}>\" -write #{dest_display}"
		# convert icon, write out
		cmd_line += " -geometry \"#{Photo::ICON_SIZE}X#{Photo::ICON_SIZE}>\" #{dest_icon}"
		success = Kernel.system cmd_line
		raise("Photo resize failed" + $?.to_s) unless success
	end
	
	def self.storeFile(photo, file_path)
		photo.save
		dir = self.get_user_dir(photo)
		ext = File.extname( photo.display_name ).downcase
		ext = ".img" unless [".jpg", ".gif", ".png"].index(ext)
		destName = photo.id.to_s + ext
		dest = File.join(dir, destName)
		FileUtils.mv(file_path, dest)
		photo.md5 = Digest::MD5.hexdigest(File.read(dest))
		photo.storage = destName
		photo.save
		# file post-processing: orient, and generate sizes
		self.auto_orient(photo) 
		self.resize(photo)
	end
	
	def self.destroyFile(photo)
		begin
			File.delete(photo.file_path())
		rescue => ex
			PB.logger.error "Could not destroy file #{fileName} " + ex.message
		end
		begin 
			File.delete(photo.file_path(:icon)) 
		rescue 
		end
		begin 
			File.delete(photo.file_path(:display)) 
		rescue 
		end
		photo.storage = ""
		photo.md5 = ""
		photo.save
		PB.logger.info("photo file deleted")
	end
	
end

end