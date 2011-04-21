require 'pony'
require 'net/pop'
require 'mysql'
require 'date'

module Nag
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

    def method_missing(method_sym, *args, &block)
      if method_sym.to_s =~ /#{IDKEYS.map { |k| "(#{k.to_s})_id_for" }.join('|')}/
        @id_maps[$1.to_sym][args[0].downcase]
      else
        super
      end
    end
  end


  class Nag
    Recipient = Struct.new(:name, :last_day, :last_client, :last_project)

    def initialize(*names)
      @td = TimesheetData.new(my)
      @recipients = []

      names.each do |name|
        @recipients << recipient_for(name)
      end

      Pony.options = {
        :from => 'nag@carbonfive.com',
        :subject => 'Timesheet Reminder',
        :via => :smtp,
        :via_options => { :address => 'smtp.carbonfive.com', :enable_starttls_auto => false }
      }
    end

    def nag
      @recipients.select {|r| should_nag? r }.each do |r|
        merge = {'Day' => Date.today.to_s, 'Duration' => 8, 'Client' => r.last_client, 'Project' => r.last_project, 'Task_Notes' => '', 'Location' => 'C5 SF Office' }

        body = "Fill out your timesheet: http://timesheet.carbonfive.com or respond to this email:\n"
        merge.each do |k, v|
         body << "#{k}: #{v}\n"
        end

        Pony.mail(:to => "#{r.name}@carbonfive.com", :body => body)
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
      Date.parse(recipient.last_day) > Date.today - 1
    end
  end
end

nag = Nag::Nag.new('erik')
nag.nag
nag.close

my = Mysql::new("localhost", "root", "", "timesheet_production")
td = Nag::TimesheetData.new(my)

nag_password = 'kic-vup-kewv-'

Net::POP3.enable_ssl(OpenSSL::SSL::VERIFY_PEER)
Net::POP3.start('pop.gmail.com', 995, 'nag@carbonfive.com', nag_password) do |pop|
  pop.each_mail do |m|
    message = m.pop
    if message[/Subject:.*Timesheet Reminder/]
      post_params = {}
      post_params['worker'] = message.match(/From:.*<(.*)@carbonfive.com>/)[1]

      email_values.each_key do |k| 
        matched = message.match(/#{k}:(.*)/)
        post_params[k.downcase] = matched[1].strip
      end

      id_maps.each_key do |k|
        post_params["#{k.to_s}_id"] = id_maps[k][post_params[k.to_s].downcase]
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
my.close
