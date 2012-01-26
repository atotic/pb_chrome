require 'logger'
require 'log4r'

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
