#!/usr/bin/env ruby
##require "cgi"
require "date"
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
  mail_body = generate_mail_body(project_name, project_url, push_info)

  # get team members
  ignore_list = (params['ignore'] || '').split(',')
  developers = Gitlab.team_members(project.id)
    .reject { |user| ignore_list.include?(user.email) }
    .map { |user| user.email }

  # send mail
  Mail.deliver do
    to developers
    from MAIL_FROM
    subject mail_subject
    body mail_body
  end
end

def generate_mail_body(project_name, project_url, push_info)
# mail contents
mail_body = <<-MAIL_BODY 
#{push_info['user_name']} pushed new commits to #{project_name}.

  Branch: #{push_info['ref']}
  home:   #{project_url}

MAIL_BODY
mail_body += 
push_info['commits'].map {|commit|
  author = commit['author']
"  Commit: #{commit['id']}:
      #{commit['url']}:
  Author: #{author['name']} <#{author['email']}>
  Date:   #{DateTime.parse(commit['timestamp']).strftime('%Y-%m-%d (%a, %-d %b %Y)')}
  Log Message:
  -----------
  #{commit['message']}


"
}.join('') +
"Compare: #{project_url}/compare/#{push_info['before']}...#{push_info['after']}

----
This email is delivered by GitLab Web Hook."

  mail_body
end

post '/' do
  push_body = request.body.read
  send_mail(push_body)
end
