require 'pony'
require 'net/pop'

recipients = [
  'erik@carbonfive.com'
]

nag_password = 'kic-vup-kewv-'

Pony.options = {
  :from => 'nag@carbonfive.com', 
  :subject => 'Timesheet Reminder',
  :via => :smtp, 
  :via_options => { :address => 'smtp.carbonfive.com', :enable_starttls_auto => false }
}

email_values = {
  'Date' => Time.now,
  'Hours' => 8,
  'Client' => '',
  'Project' => '',
  'Description' => '',
  'Location' => 'Carbon Five SF'
}

recipients.each do |addr|
  body = "Fill out your timesheet: http://timesheet.carbonfive.com or respond to this email:\n"
  email_values.each do |k, v|
   body << "#{k}: #{v}\n" 
  end

#  Pony.mail(:to => addr, :body => body)
end

Net::POP3.enable_ssl(OpenSSL::SSL::VERIFY_NONE)
Net::POP3.start('pop.gmail.com', 995, 'nag@carbonfive.com', 'kic-vup-kewv-') do |pop|
  pop.each_mail do |m|
    message = m.pop
    if message[/Subject:.*Timesheet Reminder/]
      post_params = {}
      post_params['worker'] = message.match(/From:.*<(.*)@carbonfive.com>/)[1]
      email_values.keys.each do |k| 
        matched = message.match(/#{k}:(.*)/)
        post_params[k] = matched[1].strip
      end

      puts post_params
    end
  end
end
