#!/usr/bin/env ruby

require 'fileutils'
require 'octokit'

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
