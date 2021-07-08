rOpenSci Software Review Badges
===============================

This repository holds the code and GitHub Actions workflow to make badges for rOpenSci software reviewed packages.

Domain name: badges are served on the domain name `badges.ropensci.org` as defined in the `CNAME` file in the root of this repository

Code: The code resides in the file `update_badges.rb` in the root of thi repository. `test-data.rb` has test issue labels data used in a previous iteration and can likely be removed. A few notes about `update_badges.rb`:

    - At the top of `update_badges.rb` are two Ruby arrays - `colors` and `versions` - make sure to update these as needed to have the label colors and versions required
    - Note that the script is currently using `ropenscilabs/statistical-software-review` repository - but this can be removed and code simplified if all stats pkgs are submitted through `ropensci/software-review`

The `Gemfile` defines dependencies for the code in `update_badges.rb`. The Ruby gems `fileutils` and `json` are part of the base Ruby distribution so are not defined in `Gemfile`

The folder `svgs` holds the svg files used by `update_badges.rb`. Make sure to add svg's here if you want them to be available to the `update_badges.rb` script. The folder `pkgsvgs` is empty (except for a placeholder file so that git doesn't ignore the folder) and holds the output svg files for each issue.

A JSON file with metadata is output from the `update_badges.rb` script and is put into the path `pkgsvgs/json/onboarded.json`

The GitHub Actions workflow runs: 
    - on push, and
    - cron schedule of every 6 hours
