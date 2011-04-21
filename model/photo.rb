require 'dm-validations'
require 'dm-core'
require 'dm-migrations'
require 'dm-timestamps'

require 'model/book'
require 'fileutils'
require 'digest/md5'

#
# Photo represents photos in our system
#
class Photo
  include DataMapper::Resource
  
  property :id,           Serial 
	property :created_at,		DateTime
	property :updated_at,		DateTime
	
	property :display_name,	String
	property :storage,			String  # where is the image stored locally
	property :md5,					String  # md5 hash
	
	belongs_to :user
	has n, :books, :through => Resource
	
	def to_json(*a)
		{
      :id => self.id,
      :display_name => self.display_name,
      :md5 => self.md5
    }.to_json(*a)
	end

	def filePath()
		File.join(SvegApp.photo_dir, photo.user_id, self.storage)
	end
	
	before :destroy do |photo|
		PhotoStorage.destroyFile photo
	end
end

# Photos are stored inside SvegApp.photo_dir/:user_id/:photo_id.img
# 
class PhotoStorage
	# stores the uploaded file, and updates
	
	def self.getUserDir(photo)
		dir = File.join(SvegApp.photo_dir, photo.user_id.to_s)
		FileUtils.mkdir_p(dir)
		dir
	end
	
	def self.storeFile(photo, file_param)
		photo.save
		dir = self.getUserDir(photo)
		ext = File.extname( photo.display_name )
		ext = ".img" unless [".jpg", ".gif", ".png"].index(ext)
		destName = photo.id.to_s + ext
		dest = File.join(dir, destName)
		FileUtils.mv( file_param[:tempfile].path,  dest)
	  photo.md5 = Digest::MD5.hexdigest(File.read(dest))
		photo.storage = destName
		photo.save
	end
	
	def self.destroyFile(photo)
		fileName = File.join(self.getUserDir(photo), photo.storage)
		begin
			File.delete(fileName)
			photo.storage = ""
			photo.md5 = ""
			LOGGER.info("photo file deleted")
		rescue => ex
			LOGGER.error "Could not destroy file #{fileName} " + ex.message
		end
	end
end
