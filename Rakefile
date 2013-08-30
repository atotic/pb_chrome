require 'rake'
require 'rake/testtask'
require_relative '../pb_server/config/settings'

namespace :chrome do
	desc "Resets chrome profile"
	task :reset do
		puts `git reset --hard HEAD`
		Rake::Task[:'chrome:update_pdf_saver'].execute
		Rake::Task[:'chrome:update_daemon_paths'].execute
	end

	desc "Updates the extension location in chrome preferences"
	task :update_pdf_saver do
		pref_file = './chromium_profile/Default/Preferences'
		script = IO.read(pref_file)
		new_path = File.join(File.dirname(__FILE__), 'pdf_saver_extension/extension')
		script.gsub!(/\/Users\/atotic\/code\/pb_chrome\/pdf_saver_extension\/extension/, new_path)
		File.open(pref_file, 'w', 0755) {|f| f << script }
		puts 'pdf_saver_extension path updated'
	end

	desc "Updates paths in chrome_daemon.sh "
	task :update_daemon_paths do
		script_path = 'bin/linux_64/chrome_daemon.sh'
		script = IO.read(script_path)
		script.sub!(/^LOGDIR=(.*)$/, "LOGDIR=#{SvegSettings.chrome_log_dir}")
		script.sub!(/^CHROME_BIN=(.*)$/, "CHROME_BIN=#{SvegSettings.chrome_binary}")
		script.sub!(/^CHROME_PROFILE=(.*)$/, "CHROME_PROFILE=#{SvegSettings.chrome_profile_dir}")
		File.open('bin/linux_64/chrome_daemon.sh', 'w', 0755) { |f| f << script}
		puts 'chrome_daemon.sh updated'
	end

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
end
