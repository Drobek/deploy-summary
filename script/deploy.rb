#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'pivotal-tracker' #https://github.com/jsmestad/pivotal-tracker 
require 'mail'
require 'net/smtp'
require 'heroku-api'
require 'github_api'
require "uri"


ENV["RAILS_ENV"] ||= "development"
require "#{File.dirname(__FILE__)}/../config/environment.rb"

PIVOTAL_PROJECT_ID = 444391
PIVOTAL_ACCESS_TOKEN = 'a479c65816fd6910ebfbe0c3700c6900'
GITHUB_ACCESS_TOKEN = 'c2c039387a8fa7007b37116a516606c4bc07afab'
HEROKU_API_KEY = '61dcc21f-0167-46cc-b1c5-cae0721e05ec'

class Commit
	@author_name
	@author_email
	@commiter_name
	@commiter_email
	@message
	@story_id
	@story_type
	attr_accessor :author_name, :author_email, :commiter_name, :commiter_email, :message, :story_id, :story_type
	#author_name, author_email, commiter_name, commiter_email and message are self explaining
	#story_id is ID of related story or nil
	#story_type is one of these: delivered, in_progress, nil

	def initialize(author_name, author_email, commiter_name, commiter_email, message, story_id, story_type)
		@author_name = author_name
		@author_email = author_email
		@commiter_name = commiter_name
		@commiter_email = commiter_email
		@message = message
		@story_id = story_id
		@story_type = story_type
	end

	def to_s
		return "<\#Commit by =#{self.author_name} (#{self.author_email}) story_id: #{self.story_id} story_type: #{self.story_type})>"
	end

end

def get_commits_from_github
	uri = URI.parse("https://api.github.com/repos/clarityfm/clarity/commits?access_token=c2c039387a8fa7007b37116a516606c4bc07afab")
	http = Net::HTTP.new(uri.host, uri.port)
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_NONE

	request = Net::HTTP::Get.new(uri.request_uri)
	response = http.request(request)
	return response.body
end

#def get_releases
#	heroku = Heroku::API.new(:api_key => HEROKU_API_KEY)
#	releases = heroku.get_releases('clarityfm-deploy-summary')
#	p releases.body.first
#	p releases.body.last
#end

def get_story_from_message(message)
	story_id = nil
	story_type = nil
	if message
		message.sub(/\[.*#(.*?)\]/) { story_id = $1 }
		message.sub(/\[(.*?)#.*\]/){ story_type = $1 }
	end
	if (!story_id && !story_type && message.downcase.include?('merge'))
		story_type = 'merge'
	end
	ret = [story_id,story_type]
	return ret
end

def remove_story_tag_from_message(message)
	if message=~/\[(.*)\]/
		res = nil
		message.sub(/\[(.*)\](.*)/) { res = $2 }
		return res
	end
	return message
end

def get_commits
	commits = Array.new
	parsed = JSON.parse(get_commits_from_github())
	parsed.each do |act_data|
		message = act_data['commit']['message']
		story = get_story_from_message(message)
		story_id = story[0]
		story_type = story[1]
		message = remove_story_tag_from_message(message)
		
		act_commit = Commit.new(act_data['commit']['author']['name'],
			act_data['commit']['author']['email'],
			act_data['commit']['committer']['name'],
			act_data['commit']['committer']['email'],
			message,
			story_id,
			story_type
		)
		commits.push act_commit
	end
	return commits
end

def get_pivotal_project
	PivotalTracker::Client.token = PIVOTAL_ACCESS_TOKEN
	PivotalTracker::Client.use_ssl = true
	return PivotalTracker::Project.find(PIVOTAL_PROJECT_ID)
end

def get_story_info(project, story_id)
	return project.stories.find(story_id)
end

def distribute_commits
	delivered = Array.new
	in_progress = Array.new
	other = Array.new
	commits = get_commits()
	project = get_pivotal_project
	commits.each do |commit|
		story_id = commit.story_id
		story_type = commit.story_type
		if (story_id)
			if (story_type && (story_type.include?('fix') || story_type.include?('deliver')))
				story = get_story_info(project, commit.story_id)
				act = [story.name, story.url, story.description]
				delivered.push(act)
			else
				story = get_story_info(project, commit.story_id)
				act = [story.name, story.url, commit.message]
				in_progress.push(act)
			end
		else
			if (story_type != 'merge')
				act = [commit.author_name, commit.author_email, commit.message]
				other.push(act)
			end
		end
	end
	return [delivered, in_progress, other]
end

def compose_email(commits)
	body = "<h1>Deploy summary</h1>"
	body += "<h2>Delivered stories</h2><ul>"
	delivered = commits[0]
	delivered.each do |commit|
		body += "<li> #{commit[0]} <a href=\"#{commit[1]}\">#{commit[1]}</a>: #{commit[2]}</li>"
	end
	body += "</ul><h2>In progress stories</h2><ul>"
	in_progress = commits[1]
	in_progress.each do |commit|
		body += "<li> #{commit[0]} <a href=\"#{commit[1]}\">#{commit[1]}</a>: #{commit[2]}</li>"
	end
	body += "</ul><h2>Other commits</h2><ul>"
	other = commits[2]
	other.each do |commit|
		body += "<li> #{commit[0]} (#{commit[1]}): #{commit[2]}</li>"
	end
	body += "</ul>"
	return body
end

def send_email(text)
	#TODO: chenge to other smtp server
	options = { :address              => "smtp.gmail.com",
		:port                 => 587,
		:user_name            => 'deploy.summary@gmail.com',
		:password             => 'deploy128',
		:authentication       => 'plain',
		:enable_starttls_auto => true  }

	Mail.defaults do
		delivery_method :smtp, options
	end

	Mail.deliver do
		to DEFAULT_TO_EMAIL
		from 'ondrej.maly128@gmail.com' #TODO: change to last commiter or any preset email
		subject 'Deploy summary'
		text_part do
			Nokogiri::HTML(text).text
		end
		html_part do
			content_type 'text/html; charset=UTF-8'
			body text
		end
	end
end

del = distribute_commits()
text = compose_email(del)
send_email(text)
