require 'config/settings'
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

#class Log4r::Logger; alias_method :write, :debug; end

module PB
  # command line utilites
  SVEG_FORMATTER =Log4r::PatternFormatter.new(
    :pattern => "%d %l %c %m",
    :date_pattern => "%-m/%e %I:%M:%S"
  )
  
  def self.get_logger(name) 
    l = Log4r::Logger.new(name)
    l.add Log4r::FileOutputter.new("#{name}.info", { 
      :filename => File.join(SvegSettings.log_dir, "#{name}.info" ), 
      :formatter => PB::SVEG_FORMATTER })
    l
  end

  class CommandLine
    
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
    
    def self.get_merge_pdfs(target_pdf, pdf_file_list)
      cmd_line = SvegSettings.pdf_toolkit_binary.dup
  		pdf_file_list.each do |pdf|
  			cmd_line << " " << pdf
  		end
  		cmd_line << " cat output #{target_pdf}"
  		cmd_line
    end
  end
end