require 'pony'
require 'net/pop'
require 'mysql'
require 'date'

module Nag
  NAG_KEYS = %w'Day Duration Client Project Task_Notes Location'

  class TimesheetData
    IDKEYS = [ :worker, :client, :project, :location ]

    def initialize(my)
      @id_maps = {}

      IDKEYS.each do |k|
        @id_maps[k] = {}
        sql = "select name, id from #{k}s"
        res = my.query(sql)
        res.each { |r| @id_maps[k][r[0].downcase] = r[1] }
      end
    end

    METHOD_REGEX = /(#{IDKEYS.map(&:to_s).join('|')})_id_for/
    def method_missing(method_sym, *args, &block)
      match = method_sym.to_s.match(METHOD_REGEX)
      if match
        @id_maps[match[1].to_sym][args[0].downcase]
      else
        super
      end
    end
  end


  class Nag
    Recipient = Struct.new(:name, :last_day, :last_client, :last_project)

    def initialize
      @td = TimesheetData.new(my)
    end

    def nag(*names)
      initialize_messaging

      recipients_for(names).select {|r| should_nag? r }.each do |r|
        merge = Hash[NAG_KEYS.zip([ Date.today.to_s, 8, r.last_client, r.last_project, '', 'C5 SF Office' ])]

        body = "Fill out your timesheet: http://timesheet.carbonfive.com or respond to this email:\n\n"
        merge.each do |k, v|
         body << "#{k}: #{v}\n"
        end

        Pony.mail(:to => "#{r.name}@carbonfive.com", :body => body)
      end
    end

    def collect_responses
      nag_password = 'kic-vup-kewv-'

      Net::POP3.enable_ssl(OpenSSL::SSL::VERIFY_PEER)
      Net::POP3.start('pop.gmail.com', 995, 'nag@carbonfive.com', nag_password) do |pop|
        pop.each_mail do |m|
          message = m.pop
          if message[/Subject:.*Timesheet Reminder/]
            post_params = {}
            post_params['worker'] = message.match(/From:.*<(.*)@carbonfive.com>/)[1]

            NAG_KEYS.each do |k|
              matched = message.match(/#{k}:(.*)/)
              post_params[k.downcase] = matched[1].strip
            end

            TimesheetData::IDKEYS.each do |k|
              post_params["#{k.to_s}_id"] = @td.send("#{k}_id_for".to_sym, post_params[k.to_s])
              post_params.delete(k.to_s)
            end

            puts post_params
            sql ="insert into taskentries (#{post_params.keys.join(',')},created_at, updated_at) values (#{post_params.keys.collect { |f| '?' }.join(',')},?,?);"
            st = my.prepare(sql)
            st.execute(*post_params.values, Time.now, Time.now)
            st.close
          end
        end
      end
    end

    def my
      @my ||= Mysql::new("localhost", "root", "", "timesheet_production")
    end

    def close
      my.close
    end

    private

    LATEST_INFO_FMT = %{
      select day, clients.name, projects.name from taskentries
        join clients on clients.id = client_id
        join projects on projects.id = project_id
      where worker_id = %s
      order by day desc limit 1
    }

    def initialize_messaging
      Pony.options = {
        :from => 'nag@carbonfive.com',
        :subject => 'Timesheet Reminder',
        :via => :smtp,
        :via_options => { :address => 'smtp.carbonfive.com', :enable_starttls_auto => false }
      }
    end

    def recipients_for(names)
      names.collect { |name| recipient_for(name) }
    end

    def recipient_for(name)
      sql = sprintf(LATEST_INFO_FMT, @td.worker_id_for(name))

      begin
        day, client, project = my.query(sql).fetch_row
        Recipient.new(name, day, client, project)
      rescue
        Recipient.new(name)
      end
    end

    def should_nag?(recipient)
      Date.parse(recipient.last_day) < Date.today - 1
    end
  end
end
