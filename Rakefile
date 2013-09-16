require 'rake'
require 'fileutils'
require 'rake/testtask'
require_relative '../pb_server/config/settings'

RAKE_DIR = File.dirname(__FILE__)

namespace :chrome do

	desc "Download binaries"
	task :download_binaries do
		STDERR.write "Filed a support request at github on how to do this"
		# download the binaries to bin (platform dependent)
		# gunzip
		# We on the API side of things try to keep up with the web site, but there's so... much... shipping.
		# Releases are one of those things we'd love to add to the API soon, but we can't promise when we'll roll that out. Keep an eye on the developer docs for updates if/when we offer a Releases API.
		# Cheers,
		# Wynn Netherland
		# Developer, GitHub
	end

	desc "Package binary"
	task :package_binary do
		# should do something here
		home_dir=File.expand_path("~")
		pb_chrome_dir=File.dirname(__FILE__)
		case (SvegSettings.platform)
		when :mac
			dest_dir = File.join(pb_chrome_dir, "bin", "mac")
			dest_tar = File.join(pb_chrome_dir, "chrome.mac.tar.gz")
			src_dir = File.join(home_dir, "chromium", "src", "out", "Release")
			abort "Chromium binary does not exist #{src_dir}" unless File.exists? src_dir
			FileUtils.rm_rf( dest_dir )
			FileUtils.mkdir_p( dest_dir )
			FileUtils.cp_r( File.join(src_dir, "Chromium.app"), dest_dir)
			`pushd #{dest_dir}; tar cvzf #{dest_tar} *; popd`
			puts "binary archive created"
		when :linux
			dest_dir = File.join( pb_chrome_dir, "bin", "linux")
			dest_tar = File.join( pb_chrome_dir, "chrome.linux.tar.gz")
			src_dir = File.join(home_dir, "chromium", "src", "out", "Release")
			abort "Chromium binary does not exist #{src_dir}" unless File.exists? src_dir
			FileUtils.rm_rf( dest_dir )
			FileUtils.mkdir_p( dest_dir )
			['chrome', 'chrome.pak', 'chrome_100_percent.pak', 'resources.pak', 'locales'].each do |f| 
				file = File.join( src_dir, f)
				puts file
				FileUtils.cp_r(file, dest_dir )
			end
			pwd = Dir.pwd
			Dir.chdir(dest_dir)
			`tar cvzf #{dest_tar} *`
			Dir.chdir(pwd)
		end
	end

end
