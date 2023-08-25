#!/usr/bin/env Rscript

library (jsonlite)

# SET statistical software review colors and versions
## svg_map gets created below from these
## doing it this way assumes you always have all versions for each color
colors <- c ("gold", "silver", "bronze")
versions <- c ("0.1", "0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8", "0.9")

# clean out pkgsvgs dir
flist <- list.files ("pkgsvgs", full.names = TRUE, pattern = "\\.svg$")
if (length (flist) > 0L) {
    file.remove (flist)
}

# get issues data
cmd0 <- "gh issue list --repo ropensci/software-review --state all --limit 50"
sr_labels <- c (
    "1/editor-checks",
    "2/seeking-reviewer\\(s\\)",
    "3/reviewer\\(s\\)-assigned",
    "4/review\\(s\\)-in-awaiting-changes",
    "5/awaiting-reviewer\\(s\\)-response",
    "6/approved" # in various versions; see below
)
#
# Add badges only for these labels. Note that the gh cli '--label' filter is
# strict 'AND'. Separate calls must be made for 'OR':
badged_labels <- 3:6
f <- tempfile (fileext = ".tsv")
dat <- lapply (sr_labels [badged_labels], function (i) {
    cmd <- paste (cmd0, "--label", i)
    system (paste0 (cmd, " > ", f))
    dat <- read.delim (f, sep = "\t", header = FALSE)
    return (dat)
})
file.remove (f)

dat <- do.call (rbind, dat)
names (dat) <- c ("number", "state", "title", "labels", "date")

stats_grade <- t (vapply (dat$labels, function (i) {
    grade <- regmatches (i, regexpr ("approved\\-[a-z]+\\-v[0-9]\\.[0-9]+", i))
    if (length (grade) == 0L) {
        grade <- version <- NA_character_
    } else {
        version <- gsub ("^.*\\v", "", grade)
        grade <- gsub ("^approved\\-|\\-v[0-9]\\.[0-9]+$", "", grade)
    }
    c (grade, version)
}, character (2L)))

# 'stats_grade' then holds all main labels for each approved issue. Current
# labels are:
# - 6/approved
# - 6/approved-bronze-v0.1
# - 6/approved-bronze-v0.2
# - 6/approved-silver-v0.1
# - 6/approved-silver-v0.2
# - 6/approved-gold-v0.1
# - 6/approved-gold-v0.2

svg_names <- list.files ("./svgs", full.names = TRUE, pattern = "\\.svg$")
svg_name_map <- apply (stats_grade, 1, function (i) {
    out <- grep (paste0 (i, collapse = "-v"), svg_names)
    ifelse (length (out) == 0L, NA_integer_, out)
})
svg_name_map <- svg_names [svg_name_map] # That fills stats badges
# Then fill standard non-stats "peer-reviewed" badges:
index <- which (grepl ("6\\/approved", dat$labels) & is.na (svg_name_map))
svg_name_map [index] <- grep ("peer\\-reviewed", svg_names, value = TRUE)
# Then "pending" for stages 3-5 inclusive:
index <- which (grepl ("3\\/|4\\/|5\\/", dat$labels) & is.na (svg_name_map))
svg_name_map [index] <- grep ("pending", svg_names, value = TRUE)
# And finally, "unknown" for any others:
svg_name_map [which (is.na (svg_name_map))] <- grep ("unknown", svg_names, value = TRUE)

svg_copy <- data.frame (
    svg_from = svg_name_map,
    svg_to = file.path ("pkgsvgs", paste0 (dat$number, "_status.svg"))
)

chk <- apply (svg_copy, 1, function (i) file.copy (i [1], i [2], overwrite = TRUE))

# copy CNAME file to gh-pages
file.copy ("CNAME", 'pkgsvgs/', overwrite = TRUE)

# ---------------------------------------
# Then create onboarded.json:
status <- gsub ("^.*svgs\\/|\\.svg$", "", svg_copy$svg_from)
rgx <- c ("\\-v[0-9].*$", "^[a-z]+\\-v")
rgx_dat <- lapply (rgx, function (i) {
    out <- rep (NA_character_, length (status))
    index <- grep (i, status)
    out [index] <- gsub (i, "", status [index])
    return (out)
})
json_input <- data.frame (
    number = dat$number,
    status = status,
    stats_grade = rgx_dat [[1]],
    stats_version = rgx_dat [[2]]
)
json_input$status [which (!is.na (json_input$stats_grade))] <- "peer-reviewed"

json_input <- data.frame (
    number = dat$number,
    status = gsub ("^.*svgs\\/|\\.svg$", "", svg_copy$svg_from)
)
rgx <- "\\-v[0-9].*$"
index <- grep (rgx, json_input$status)
json_input$stats_grade <- NA_character_
json_input$stats_grade [index] <- gsub (rgx, "", json_input$status [index])

rgx <- "^[a-z]+\\-v"
index <- grep (rgx, json_input$status)
json_input$stats_version <- NA_character_
json_input$stats_version [index] <- gsub (rgx, "", json_input$status [index])

# Then run a 'gh issue view' for each issue to get the package metadata:
pkg_data <- t (apply (json_input, 1, function (i) {

    issue_number <- i [1]

    # Package name:
    cmd <- paste ("gh issue view", issue_number, "--repo ropensci/software-review")
    issue_body <- system (cmd, intern = TRUE)

    regex_ptns <- rbind (
        c ("^Package\\:", "^Package:(\\s?)|\\r$|https\\:\\/\\/github\\.com\\/.*\\/.*"),
        c ("^[Vv]ersion\\:", "^[Vv]ersion\\:(\\s)|\\r|"),
        c ("^author\\:", "^author\\:(\\s?)|\\r$|")
    )
    regex_data <- apply (regex_ptns, 1, function (i) {
        dat <- grep (i [1], issue_body, value = TRUE) [1]
        if (!is.null (dat)) {
            dat <- gsub (i [2], "", dat)
        }
        return (dat)
    })

    c (
        pkg = regex_data [1],
        version = regex_data [2],
        user = regex_data [3]
    )
}))

json_data <- data.frame (
    pkgname = pkg_data [, 1],
    submitted = pkg_data [, 3],
    iss_no = json_input$number,
    status = json_input$status,
    version = pkg_data [, 2],
    stats_version = json_input$stats_version
)

jdir <- file.path ("pkgsvgs", "json")
if (!dir.exists (jdir)) {
    dir.create (jdir)
}
write_json (json_data, file.path (jdir, "onboarded.json"), pretty = TRUE, na = "null")
