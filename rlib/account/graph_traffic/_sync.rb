#!/usr/local/bin/ruby
require 'rubygems'
require 'net/ssh'
require 'net/scp'

# Quick hack to install changes. Will sort out something better :)

WWW_SRV = 'db.wikarekare.org'
RLIB_DIR = '/wikk/rlib/'

# Scp a file
def upload_file(scp, source, dest)
  puts "scp #{source} #{dest}"
  begin
    scp.upload!( source, dest )
  rescue Exception => e
    puts "Scp failed with error: #{e}"
  end
end

# Scp an entire directory
def upload_directory(host, destination)
  # use a persistent connection to transfer files
  begin
    Net::SCP.start(host, 'root', keys: [ '/Users/rbur004/.ssh/id_rsa' ]) do |scp|
      # upload a file to a remote server
      Dir.open('.').each do |filename|
        if filename =~ /^.+\.rb$/ # ignore parent, and current directories.
          upload_file(scp, filename, destination )
        end
      end
    end
  rescue Exception => e
    puts "#{e}"
  end
end

Dir.chdir "#{File.dirname(__FILE__)}" # put here for Atom editor. Normally we would be here but atom leaves us in the parent project directory rather then the scripts subdirectory.

upload_directory(WWW_SRV, "#{RLIB_DIR}/account/graph_traffic")
