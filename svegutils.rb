require 'config/settings'
require 'logger'
require 'log4r'
require "sfl"

class Log4r::GrowlOutputter < Log4r::Outputter
  require 'growl'
  def canonical_log(logevent)
    return unless logevent.level > 2 # errors and above make it to growl
    Growl.notify {
      self.message = logevent.data.to_s
      self.title = logevent.fullname
    }
  end
end

class ::Logger; alias_method :write, :<<; end

module PB
  # command line utilites
  class CommandLine
    def self.launch_chrome
      pid = Kernel.spawn(SvegSettings.chrome_binary,
                        "--user-data-dir=#{SvegSettings.chrome_profile_dir}",
                        "--no-sandbox",
                        :chdir => SvegSettings.chrome_profile_dir,
                        :out => File.join(SvegSettings.log_dir, "chromepdf.stdout"),
                        :err => File.join(SvegSettings.log_dir, "chromepdf.stderr"))
      Process.detach(pid)
      pid
    end
    
    def self.get_chromium_pid
      ps = `ps -A -o pid,comm`.split("\n")
      ids = ps.collect do |i| 
        if i.include? SvegSettings.chrome_binary then
          m = i.match(/(\d+)/)
          m.length > 0 ? m[0].to_i : nil
        else
          nil
        end
      end
      ids.compact!
      ids.sort
      ids.length > 0 ? ids[0] : false
    end

    def self.launch_pdf_saver()
      Kernel.spawn({}, "bin/thin start -C pdf_saver_server.yml -e #{SvegSettings.environment.to_s}")
    end
    
    def self.get_merge_pdfs(target_pdf, pdf_file_list)
      cmd_line = SvegSettings.pdf_toolkit_binary
  		pdf_file_list.each do |pdf|
  			cmd_line << " " << pdf
  		end
  		cmd_line << " cat output #{target_pdf}"
  		cmd_line
    end
  end
end