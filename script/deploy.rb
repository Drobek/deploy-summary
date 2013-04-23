#!/usr/bin/env ruby

require 'rubygems'
require 'json'

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
		return "<\#Commit by =#{self.author_name} (#{self.author_email}) story_id: #{self.story_id})>"
	end

end
