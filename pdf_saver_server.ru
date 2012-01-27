#thin start -C pdf_saver_server.yml
#require 'ruby-debug'

require 'settings'
require 'logutils'
require 'app/book2pdf_job'

# SERVER
def handle_test
  success_response = [  200, { 
        'Content-Type' => 'text/plain',
        'Content-Length' => '7',
      },  ['success']]
  success_response
end

def handle_work
  task = PB::ChromeHTMLToPDFTask.first(:processing_stage => PB::ChromeHTMLToPDFTask.STAGE_WAITING)
  return [ 204, { 'Content-Type' => 'text/plain',
                  'Content-Length' => 10
                }, ['no content']] unless task
  task.processing_stage = PB::ChromeHTMLToPDFTask.STAGE_DISPATCHED_TO_CHROME
  task.save
  [200, {'Content-Type' => 'application/json'}
    task.to_json]
  # find a job, return 200 on success
end

def pdf_done
  
end

def pdf_fail
end

app = proc do |env|
  case 
    when env['PATH'].eql? "/test" then return handle_test
    when env['PATH'].eql? "/get_pdf_work" then return handle_work
    when env['PATH'].eql? "/pdf_done" then return handle_pdf_done
    when env['PATH'].eql? "/pdf_fail" then return handle_pdf_fail
    else return [404, {}, ["Not found"]]
  end
  return success_response if (env['PATH_INFO'].eql?("/test"))
  query = Rack::Utils.parse_query(env['QUERY_STRING'])
  return [400, {}, "Bad request. Need url in query params"] unless query['url']
  url = query['url'].sub(/:/, "_")
  begin
    file_name = get_store_file_name(url, pdf_map)
    puts "Creating PDF #{file_name} #{Time.now()}"
    # write out the file
    File.open(File.join($pdf_directory, file_name), "wb") do |f|
      f.write(env['rack.input'].read)
    end
    pdf_map[url] = file_name
    write_pdf_map(pdf_map)
  rescue => ex
    return [400, { 'Content-Type' => 'text/plain'}, "Unexpected server error: " + ex.to_s]
  end
  success_response
end

use Rack::CommonLogger, Logger.new(File.join(SvegSettings.log_dir, "pdf_saver_server.log"))

run app