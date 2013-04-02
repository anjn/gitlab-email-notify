#!/usr/bin/env ruby
require "cgi"
require "json"
require "gitlab"
require "mail"

# config
GITLAB_URL = 'http://FIXME/'
GITLAB_TOKEN = 'FIXME'
MAIL_FROM = 'FIXME'

Mail.defaults do
  delivery_method :smtp, {
    :enable_starttls_auto => true,
    :address => "smtp.gmail.com",
    :port => 587,
    :domain => "gmail.com",
    :authentication => :plain,
    :user_name => "FIXME",
    :password => "FIXME",
  }
end

# cgi
cgi = CGI.new
print "Content-type: text/html\n\n"

# get push info
push_info = JSON.parse(cgi.params.keys[0])

# gitlab setup
Gitlab.endpoint = "#{GITLAB_URL}api/v3"
Gitlab.private_token = GITLAB_TOKEN

# get project name
project_url  = push_info['repository']['homepage']
project_name = project_url.sub(GITLAB_URL, '')

# get project info
project = Gitlab.projects.find do |x|
  x.path_with_namespace == project_name
end

exit if project.nil?

# mail contents
mail_subject = "GitLab | #{project_name} | notify"
mail_body = 
"#{push_info['user_name']} pushed new commits to #{project_name}.

* Project page
 - #{project_url}

* Commit info
"

push_info['commits'].each do |commit|
  author = commit['author']
  mail_body += " - by #{author['name']} <#{author['email']}>\n"
  mail_body += "   #{commit['message']}\n\n"
end

mail_body += "----
This email is delivered by GitLab Web Hook."

# get team member & send mail
Gitlab.team_members(project.id).each do |user|
  mail = Mail.new do
    to user.email
    from MAIL_FROM
    subject mail_subject
    body mail_body
  end
  mail.deliver!
end
