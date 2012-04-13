require 'rake'
require 'rake/testtask'

namespace :chrome do
  desc "Resets chrome profile"
  task :reset do
    puts `git reset --hard HEAD`
    Rake::Task[:'chrome:update_pdf_saver'].execute
  end

  desc "Sets profile "
  task :update_pdf_saver do
  	pref_file = './chromium_profile/Default/Preferences'
  	script = IO.read(pref_file)
  	new_path = File.join(File.dirname(__FILE__), 'pdf_saver_extension/extension')
  	script.gsub!(/\/Users\/atotic\/code\/pb_chrome\/pdf_saver_extension\/extension/, new_path)
  	File.open(pref_file, 'w', 0755) {|f| f << script }
  	puts 'pdf_saver_extension path updated'
  end
end
