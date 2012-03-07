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
#	property :storage,			String  # where is the image stored locally
#	property :md5,					String  # md5 hash

	plugin :timestamps
	
	many_to_one :user
	many_to_many :books
	
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
	  LOGGER.info("destroying photo #{self.pk}#{self.display_name}")
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
	
	def self.get_cmd_resize(size, src, dest)
		src = File.expand_path(src)
		dest = File.expand_path(dest)
		"sips -Z #{size} #{src} --out #{dest}"
	end
	
	def self.createDifferentSizes(photo)
		src = photo.file_path
		dest = photo.file_path('icon')
		cmd_line = self.get_cmd_resize(128, src, dest)
		success = Kernel.system cmd_line
		raise ("Photo resize failed " + $?.to_s) unless success
		dest = photo.file_path('display')
		cmd_line = self.get_cmd_resize(1024, src, dest)
		success = Kernel.system cmd_line
		raise ("Photo resize failed " + $?.to_s) unless success
	end
	
	def self.storeFile(photo, file_path)
		photo.save
		dir = self.get_user_dir(photo)
		ext = File.extname( photo.display_name ).downcase
		ext = ".img" unless [".jpg", ".gif", ".png"].index(ext)
		destName = photo.id.to_s + ext
		dest = File.join(dir, destName)
		FileUtils.mv( file_path,  dest)
	  photo.md5 = Digest::MD5.hexdigest(File.read(dest))
		photo.storage = destName
		photo.save
		self.createDifferentSizes(photo)		
	end
	
	def self.destroyFile(photo)
		begin
			File.delete(photo.file_path())
		rescue => ex
			LOGGER.error "Could not destroy file #{fileName} " + ex.message
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
		LOGGER.info("photo file deleted")
	end
	
end

end