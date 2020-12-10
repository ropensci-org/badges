#!/usr/bin/env ruby

require 'fileutils'
require 'octokit'
require 'json'

# clean out pkgsvgs dir
FileUtils.rm_rf(Dir.glob("pkgsvgs/*"))

# get issues data
con = Octokit::Client.new :access_token => ENV['GITHUB_PAT']
con.auto_paginate = true # do automatic pagination
issues = con.issues('ropensci/software-review', state: "all");

# filter to labels with either review or seeking via grep
iss_pending = issues.select { |z| z.labels.map(&:name).grep(/review|seeking/).any? };
# filter to labels with approved via grep
iss_peer_rev = issues.select { |z| z.labels.map(&:name).grep(/approved/).any? };
# make out of bounds value
outofbounds = issues.map(&:number).max + 1

# make file names
iss_pending_files = iss_pending.map { |e| '%s_status.svg' % e.number };
iss_peer_rev_files = iss_peer_rev.map { |e| '%s_status.svg' % e.number };
iss_unknown_files = (outofbounds...(outofbounds + 50)).map { |e| '%s_status.svg' % e }

# copy svg's for each submission
svg_pending = "svgs/pending.svg"
iss_pending_files.map { |e| FileUtils.cp(svg_pending, 'pkgsvgs/' + e) }

svg_peer_reviewed = "svgs/peer-reviewed.svg"
iss_peer_rev_files.map { |e| FileUtils.cp(svg_peer_reviewed, 'pkgsvgs/' + e) }

svg_unknown = "svgs/unknown.svg"
iss_unknown_files.map { |e| FileUtils.cp(svg_unknown, 'pkgsvgs/' + e) }

# copy CNAME file to gh-pages
FileUtils.cp("CNAME", 'pkgsvgs/')

# create onboarded.json
iss_hashes = [iss_pending, iss_peer_rev].flatten.map { |e|
  # issue number
  iss = e.number
  # pkg name
  pkg = e.body.scan(/(Package:)(\s.+)/)[0]
  pkg = pkg.nil? ? e.body.scan(/https:\/\/github.com\/.*\/.*\s+/).first.strip.split("/").last : pkg[1].strip
  # package version
  version = e.body.scan(/(Version:)(\s.+)/)[0]
  version = version.nil? ? nil : version[1].strip
  # submitter
  user = e.user.login
  # status
  stat_checks = [
    e.labels.map(&:name).grep(/review|seeking/).any?,
    e.labels.map(&:name).grep(/approved/).any?
  ]
  choices = ["pending","reviewed"]
  status = choices.select.with_index {|_,i| stat_checks[i]}[0]
  {"pkgname"=>pkg,"submitter"=>user,"iss_no"=>iss,"status"=>status,"version"=>version}
}
File.open("onboarded.json","w") do |f|
  f.write(JSON.pretty_generate(iss_hashes))
end
FileUtils.cp("onboarded.json", 'pkgsvgs/')
