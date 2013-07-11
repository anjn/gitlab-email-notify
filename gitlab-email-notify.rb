#!/usr/bin/env ruby
require 'json'
require 'gitlab'
require 'mail'
require 'yaml'
require 'sinatra'

config_path = File.join(File.dirname(__FILE__), 'config.yml')
config = YAML::load(File.read(config_path))

# config
GITLAB_URL = config[:gitlab][:url]
GITLAB_TOKEN = config[:gitlab][:token]
MAIL_FROM = config[:mail][:from]

deli = config[:mail][:delivery]
Mail.defaults do
  delivery_method deli[:method], deli[:options]
end

def send_mail(push_body)
  # get push info
  push_info = JSON.parse(push_body)

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
  mail_body = <<-MAIL_BODY
#{push_info['user_name']} pushed new commits to #{push_info['ref']} at #{project_name}.

* Project page
 - #{project_url}

* Commit info
  MAIL_BODY

  push_info['commits'].each do |commit|
    author = commit['author']
    permalink = "#{project_url}/commit/#{commit['id']}"
    mail_body += " - by #{author['name']} <#{author['email']}>\n"
    mail_body += "   #{permalink}\n"
    mail_body += "   #{commit['message']}\n\n"
  end

  mail_body += "----
  This email is delivered by GitLab Web Hook."

  # get team members
  # [access level] guest: 10, reporter: 20, developer: 30, master: 40
  developers = Gitlab.team_members(project.id)
    .select { |user| user.access_level >= 30 }
    .map { |user| user.email }

  # send mail
  Mail.deliver do
    to developers
    from MAIL_FROM
    subject mail_subject
    body mail_body
  end
end

post '/' do
  push_body = request.body.read
  send_mail(push_body)
end
