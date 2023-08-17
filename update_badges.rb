#!/usr/bin/env ruby

require 'fileutils'
require 'octokit'
require 'json'

# SET statistical software review colors and versions
## svg_map gets created below from these
## doing it this way assumes you always have all versions for each color
colors = ["gold", "silver", "bronze"]
versions = ["0.1", "0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8", "0.9"]

# clean out pkgsvgs dir
FileUtils.rm_rf(Dir.glob("pkgsvgs/*"))

# get issues data
con = Octokit::Client.new :access_token => ENV['GITHUB_PAT']
con.auto_paginate = true # do automatic pagination
issues = con.issues('ropensci/software-review', state: "all");

# filter to labels with either review or seeking via grep, but only on
# "official" labels starting with "[0-9]/<label>" (see #9)
iss_pending = issues.select { |z| z.labels.map{|w| w[:name]}.grep(/^[0-9]\/.*(review|seeking)/).any? };
# filter to labels with approved via grep
## ropensci review and stats review
iss_peer_rev = issues.select { |z| z.labels.map{|w| w[:name]}.grep(/approved/).any? };
# make out of bounds value, different for regular and stats review
sr_oob = issues.map(&:number).max + 1

# make file names
iss_pending_files = iss_pending.map { |e| "%s_status.svg" % e.number }

iss_peer_rev_files = iss_peer_rev.map { |e|
  suffix = !!e.url.match(/statistical/) ? "status_stats" : "status"
  path = "%s_%s.svg" % [e.number, suffix]
  color = colors.select { |str| e.labels.map{|w| w[:name]}.map { |z| z.include? str }.any? }.first
  version = versions.select { |str| e.labels.map{|w| w[:name]}.map { |z| z.include? str }.any? }.first
  [color, version, path]
}

iss_unknown_files = (sr_oob...(sr_oob + 50)).map { |e| "%s_status.svg" % e }

# copy svg's for each submission
svg_pending = "svgs/pending.svg"
iss_pending_files.map { |e| FileUtils.cp(svg_pending, 'pkgsvgs/' + e) }

# Map gold/silver/bronze and stats versions:
svg_map = colors.product(versions).map { |w| "svgs/" + w.join("-v") + ".svg"}.
  append("svgs/peer-reviewed.svg")

iss_peer_rev_files.map { |e|
  # each element e is an array of length two w/ .first and .last (or [0] and [1])
  target_svg = if e.first.nil?
    "svgs/peer-reviewed.svg"
  else
    svg_map.map {|x| x.match(e.first)}.compact.map {|w| w.string.match(e[1])}.compact.first.string
  end
  # don't write a file if target_svg is nil
  unless target_svg.nil?
    FileUtils.cp(target_svg, "pkgsvgs/" + e.last)
    # puts target_svg
  end
}

svg_unknown = "svgs/unknown.svg"
iss_unknown_files.map { |e| FileUtils.cp(svg_unknown, 'pkgsvgs/' + e) };

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
  status_checks = [
    e.labels.map{|w| w[:name]}.grep(/review|seeking/).any?,
    e.labels.map{|w| w[:name]}.grep(/approved/).any?
  ]
  choices = ["pending", "reviewed"]
  status = choices.select.with_index { |_, i| status_checks[i] }[0]
  stats_version = versions.select { |str| e.labels.map{|w| w[:name]}.map { |z| z.include? str }.any? }.first
  {
    "pkgname" => pkg,
    "submitter" => user,
    "iss_no" => iss,
    "status" => status,
    "version" => version,
    "stats_version" => stats_version || nil
  }
}
File.open("onboarded.json", "w") do |f|
  f.write(JSON.pretty_generate(iss_hashes))
end
FileUtils.mkdir('pkgsvgs/json')
FileUtils.cp("onboarded.json", 'pkgsvgs/json/')
