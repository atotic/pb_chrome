require 'config/settings'
require 'config/db'
require 'log4r'
require "sfl"
require 'app/user'
require 'app/command_stream'

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
	::Log4r::Outputter.stdout.formatter = SVEG_FORMATTER if SvegSettings.environment == :development

	@@logger = nil
	
	def self.logger
		@@logger || Log4r::Logger.root
	end

	def self.create_server_logger(name) 
		l = Log4r::Logger.new(name)
		file_out = Log4r::FileOutputter.new("#{name}.info", { 
			:filename => File.join(SvegSettings.log_dir, "#{name}.info" ), 
			:formatter => PB::SVEG_FORMATTER })
		# root outputs everything, so we can use it in libraries
		l.add file_out
		l.add Log4r::Outputter.stdout if SvegSettings.environment == :development
		l.add Log4r::GrowlOutputter.new('growlout') if SvegSettings.environment == :development
		@@logger = l
		l
	end

	# command line utilities
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

	# Sveg session maintenance
	# sets env['sveg.user'] to logged in user
	# Saves flash hash only if it has changed
	# 
	# Canonical middleware stack looks like this
	# use Rack::Session::Cookie, {
	#		:key => 'rack.session',
	#		:coder => PB::SvegSessionCoder.new,
	#		:sidbits => 32,
	#		:skip => true,	# Rack > 1.4
	#		:defer => true, # Rack < 1.4
	#	}
	#	use Rack::Flash
	#	use SvegSession
	# 
	# api test in svegsession_test.rb
	class SvegSession

		def initialize(app)
			@log_access = SvegSettings.environment == :development
			@app = app
		end

		FORMAT = %{ %s %s %s%s %s" %s %0.4f}
		def log(env, status, time_taken)
			now = Time.now
			return if env['sinatra.static_file']
			return if /assets/ =~ env["PATH_INFO"] 
			PB.logger.error "HTTP ERROR" if status >= 400
			PB.logger.info FORMAT % [
            env["sveg.user"] || "-",
            env["REQUEST_METHOD"],
            env["PATH_INFO"],
            env["QUERY_STRING"].empty? ? "" : "?"+env["QUERY_STRING"],
            env["HTTP_VERSION"],
            status.to_s[0..3],
            time_taken ]
		end

		def call(env)
			start_time = Time.now
			request = Rack::Request.new(env)
			before(env, request)
			status, headers, body = @app.call(env)
			after(env, request, status, headers, body)
			log(env, status, Time.now - start_time) if @log_access
			[status, headers, body]
		end

		def before(env, request)
			# load user to sveg.user
			PB::User.restore_from_session(env)
			PB::ServerCommand.restore_from_headers(env)
		end

		def after(env, request, status, headers, body)
			# flash propagates in headers in xhr
			if request.xhr? # ajax requests get flash headers
				headers.merge!({"X-FlashError" => env['x-rack.flash'][:error]}) if env['x-rack.flash'][:error]
				headers.merge!({"X-FlashNotice" => env['x-rack.flash'][:notice]}) if env['x-rack.flash'][:notice]
			end
			# clear out empty flash
			env['rack.session'].delete('__FLASH__') if (env['rack.session']['__FLASH__'] && env['rack.session']['__FLASH__'].empty?)
			# set cookie only if cookie has changed, or we are trying to delete it
			changed = !(env['rack.session'].eql? env['rack.session.unpacked_cookie_data'])
			changed ||= env['rack.session.options'][:expire_after] == 0
			env['rack.session.options'][:skip] = false if changed
			env['rack.session.options'][:defer] = false if changed
			PB.logger.info "Setting cookie" if changed
		end
	end

	# JSON session encoder, development use only
	class SvegSessionCoder 
		def encode(str)
			JSON.generate str
		end
		def decode(str)
			return nil if str.nil?
			p = JSON.parse str
			if p && p.has_key?('__FLASH__') then
				# flash keys are symbols, not strings, fix json encoding
				p['__FLASH__'].each_key do |key|
					if key.class == String then
						p['__FLASH__'][key.to_sym] = p['__FLASH__'].delete(key)
					end
	 			end
			end
			p
		end
	end

end