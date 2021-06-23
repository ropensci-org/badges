#!/usr/bin/env ruby

require 'fileutils'
require 'octokit'
require 'json'

# clean out pkgsvgs dir
FileUtils.rm_rf(Dir.glob("pkgsvgs/*"))

# get issues data
con = Octokit::Client.new :access_token => ENV['GITHUB_PAT']
con.auto_paginate = true # do automatic pagination
sr_issues = con.issues('ropensci/software-review', state: "all")
ssr_issues = con.issues("ropenscilabs/statistical-software-review", state: "all")
issues = sr_issues + ssr_issues

# filter to labels with either review or seeking via grep
iss_pending = issues.select { |z| z.labels.map(&:name).grep(/review|seeking/).any? };
# filter to labels with approved via grep
## ropensci review and stats review
## FIXME: using "editor-checks" here as placeholder as no stats review labels exist yet
##   probably just need "approved" regex for both regular and stats review
iss_peer_rev = issues.select { |z| z.labels.map(&:name).grep(/approved|editor-checks/).any? }
# make out of bounds value, different for regular and stats review
sr_oob = sr_issues.map(&:number).max + 1
ssr_oob = ssr_issues.map(&:number).max + 1

# make file names
iss_pending_files = iss_pending.map { |e| "%s_status.svg" % e.number }

colors = ["gold", "silver", "bronze"]
iss_peer_rev_files = iss_peer_rev.map { |e|
  suffix = !!e.url.match(/statistical/) ? "status_stats" : "status"
  path = "%s_%s.svg" % [e.number, suffix]
  color = colors.select { |str| e.labels.map(&:name).map { |z| z.include? str }.any? }.first
  [color, path]
}

iss_unknown_files = (sr_oob...(sr_oob + 50)).map { |e| "%s_status.svg" % e } +
  (ssr_oob...(ssr_oob + 50)).map { |e| "%s_status_stats.svg" % e }

# copy svg's for each submission
svg_pending = "svgs/pending.svg"
iss_pending_files.map { |e| FileUtils.cp(svg_pending, 'pkgsvgs/' + e) }

# FIXME: gold/silver/bronze need to be replaced w/ actual svg's
svg_map = {
  "regular" => "svgs/peer-reviewed.svg",
  "gold" => "svgs/stats-gold.svg",
  "silver" => "svgs/stats-silver.svg",
  "bronze" => "svgs/stats-bronze.svg"
}
iss_peer_rev_files.map { |e|
  # each element e is an array of length two w/ .first and .last (or [0] and [1])
  target_svg = e.first.nil? ? svg_map["regular"] : svg_map[e.first]
  # don't write a file if target_svg is nil
  unless target_svg.nil?
    FileUtils.cp(target_svg, "pkgsvgs/" + e.last)
  end
}

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
  choices = ["pending", "reviewed"]
  status = choices.select.with_index { |_, i| stat_checks[i] }[0]
  {"pkgname" => pkg, "submitter" => user, "iss_no" => iss, "status" => status, "version" => version}
}
File.open("onboarded.json", "w") do |f|
  f.write(JSON.pretty_generate(iss_hashes))
end
FileUtils.mkdir('pkgsvgs/json')
FileUtils.cp("onboarded.json", 'pkgsvgs/json/')
