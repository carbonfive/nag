require 'pony'
require 'net/pop'
require 'mysql'
require 'date'

recipients = [
  'erik'
]

nag_password = 'kic-vup-kewv-'

id_maps = {
  :worker => {},
  :client => {},
  :project => {},
  :location => {},
}

my = Mysql::new("localhost", "root", "", "timesheet_production")
id_maps.each_key do |k|
  sql = "select name, id from #{k}s"
  res = my.query(sql)
  res.each do |r|
    id_maps[k][r[0].downcase] = r[1]
  end
end

puts id_maps

Pony.options = {
  :from => 'nag@carbonfive.com', 
  :subject => 'Timesheet Reminder',
  :via => :smtp, 
  :via_options => { :address => 'smtp.carbonfive.com', :enable_starttls_auto => false }
}

email_values = {
  'Day' => Date.today.to_s,
  'Duration' => 8,
  'Client' => '',
  'Project' => '',
  'Task_Notes' => '',
  'Location' => 'C5 SF Office'
}

recipients.each do |addr|
  ev = email_values.dup

  current_info_sql = %{
    select clients.name, projects.name 
    from taskentries 
    join clients on clients.id = client_id 
    join projects on projects.id = project_id 
    where worker_id = #{id_maps[:worker][addr]} 
    order by day desc limit 1
  }

  begin
    res =  my.query(current_info_sql)
    ev['Client'], ev['Project'] = res.fetch_row
  rescue
  end

  body = "Fill out your timesheet: http://timesheet.carbonfive.com or respond to this email:\n"
  ev.each do |k, v|
   body << "#{k}: #{v}\n" 
  end

  Pony.mail(:to => "#{addr}@carbonfive.com", :body => body)
end

Net::POP3.enable_ssl(OpenSSL::SSL::VERIFY_PEER)
Net::POP3.start('pop.gmail.com', 995, 'nag@carbonfive.com', 'kic-vup-kewv-') do |pop|
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
        puts k
        puts post_params[k.to_s].downcase
        post_params["#{k.to_s}_id"] = id_maps[k][post_params[k.to_s].downcase]
        post_params.delete(k.to_s)
      end
      puts post_params

      
      sql ="insert into taskentries (#{post_params.keys.join(',')}) values (#{post_params.keys.collect { |f| '?' }.join(',')});"
      st = my.prepare(sql)
      st.execute(*post_params.values)
      st.close
    end
  end
end
my.close
