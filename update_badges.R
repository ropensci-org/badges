#!/usr/bin/env Rscript

# clean out pkgsvgs dir
flist <- list.files ("pkgsvgs", full.names = TRUE, pattern = "\\.svg$")
if (length (flist) > 0L) {
    chk <- file.remove (flist)
}

library (jsonlite)
library (gh)

get_gh_token <- function (token = "") {

    tryCatch (
        gitcreds::gitcreds_get ()$password,
        error = function (e) ""
    )
}

get_issues_qry <- function (org = "ropensci",
                            repo = "software-review",
                            end_cursor = NULL) {

    after_txt <- ""
    if (!is.null (end_cursor)) {
        after_txt <- paste0 (", after:\"", end_cursor, "\"")
    }

    q <- paste0 ("{
        repository(owner:\"", org, "\", name:\"", repo, "\") {
                   issues (first: 100", after_txt, ") {
                       pageInfo {
                           hasNextPage
                           endCursor
                       }
                       edges {
                           node {
                               ... on Issue {
                                   number
                                   author {
                                       login
                                   }
                                   state
                                   title
                                   labels (first: 100) {
                                       edges {
                                           node {
                                               name,
                                           }
                                       }
                                   }
                                   body
                                   url
                               }
                           }
                       }
                   }
                }
        }")

    return (q)
}

has_next_page <- TRUE
end_cursor <- NULL

number <- author <- state <- titles <- body <- NULL
labels <- event_labels <- event_dates <- event_actors <- comments <- list ()

while (has_next_page) {

    q <- get_issues_qry (
        org = "ropensci",
        repo = "software-review",
        end_cursor = end_cursor
    )
    dat <- gh::gh_gql (query = q)

    has_next_page <- dat$data$repository$issues$pageInfo$hasNextPage
    end_cursor <- dat$data$repository$issues$pageInfo$endCursor

    edges <- dat$data$repository$issues$edges

    number <- c (
        number,
        vapply (edges, function (i) i$node$number, integer (1L))
    )
    author <- c (
        author,
        vapply (edges, function (i) i$node$author$login, character (1L))
    )
    state <- c (
        state,
        vapply (edges, function (i) i$node$state, character (1L))
    )
    titles <- c (
        titles,
        vapply (edges, function (i) i$node$title, character (1L))
    )
    labels <- c (
        labels,
        lapply (edges, function (i) unname (unlist (i$node$labels$edges)))
    )
    body <- c (
        body,
        vapply (edges, function (i) i$node$body, character (1L))
    )
}

stats_grade <- t (vapply (labels, function (i) {
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


# Reduce issues down to only those with one of these labels:
sr_labels <- c (
    "1/editor-checks",
    "2/seeking-reviewer\\(s\\)",
    "3/reviewer\\(s\\)-assigned",
    "4/review\\(s\\)-in-awaiting-changes",
    "5/awaiting-reviewer\\(s\\)-response",
    "6/approved" # in various versions; see below
)
index <- vapply (labels, function (i) any (grepl (paste0 (sr_labels, collapse = "|"), i)), logical (1L))
all_numbers <- number # used to deploy "unknown" badges
number <- number [index]
author <- author [index]
state <- state [index]
titles <- titles [index]
labels <- labels [index]
body <- body [index]
stats_grade <- stats_grade [index, ]

# Reduce labels to one of 'sr_labels', noting that this removes stats
# "6/approvied-<grade><v>" labels, but those data have been extracted above.
labels <- lapply (labels, function (i) i [which (i %in% gsub ("\\\\", "", sr_labels))])
# And then to the highest-valued one:
labels <- vapply (labels, function (i) {
    n <- regmatches (i, gregexpr ("^[0-9]", i))
    i [[which.max (as.integer (unlist (n)))]]
}, character (1L))

# SET statistical software review colors and versions
## svg_map gets created below from these
## doing it this way assumes you always have all versions for each color
colors <- c ("gold", "silver", "bronze")
versions <- c ("0.1", "0.2", "0.3", "0.4", "0.5", "0.6", "0.7", "0.8", "0.9")

svg_names <- list.files ("./svgs", full.names = TRUE, pattern = "\\.svg$")
svg_name_map <- apply (stats_grade, 1, function (i) {
    out <- grep (paste0 (i, collapse = "-v"), svg_names)
    ifelse (length (out) == 0L, NA_integer_, out)
})
svg_name_map <- svg_names [svg_name_map] # That fills stats badges
# Then fill standard non-stats "peer-reviewed" badges:
index <- which (grepl ("^6", labels) & is.na (svg_name_map))
svg_name_map [index] <- grep ("peer\\-reviewed", svg_names, value = TRUE)
# Then "pending" for stages 3-5 inclusive:
index <- which (grepl ("^(3|4|5)", labels) & is.na (svg_name_map))
svg_name_map [index] <- grep ("pending", svg_names, value = TRUE)
# And finally, "unknown" for any others:
svg_name_map [which (is.na (svg_name_map))] <- grep ("unknown", svg_names, value = TRUE)

svg_copy <- data.frame (
    svg_from = svg_name_map,
    svg_to = file.path ("pkgsvgs", paste0 (number, "_status.svg"))
)

chk <- apply (svg_copy, 1, function (i) file.copy (i [1], i [2], overwrite = TRUE))

# copy CNAME file to gh-pages
file.copy ("CNAME", 'pkgsvgs/', overwrite = TRUE)

# ---------------------------------------
# Then create onboarded.json:
status <- gsub ("^.*svgs\\/|\\.svg$", "", svg_copy$svg_from)
json_input <- data.frame (
    number = number,
    author = author,
    status = gsub ("^peer\\-", "", status), # 'peer-reviewed' -> 'reviewed'
    stats_grade = stats_grade [, 1],
    stats_version = stats_grade [, 2]
)
json_input$status [which (!is.na (json_input$stats_grade))] <- "reviewed"

# Then get additional info from issue bodies:
pkg_data <- lapply (body, function (i) {
    issue_body <- strsplit (i, "\\n") [[1]]

    regex_ptns <- rbind (
        c ("^Package\\:", "^Package:(\\s?)|\\r$|https\\:\\/\\/github\\.com\\/.*\\/.*"),
        c ("^[Vv]ersion\\:", "^[Vv]ersion\\:(\\s)|\\r|")
    )
    regex_data <- apply (regex_ptns, 1, function (j) {
        dat <- grep (j [1], issue_body, value = TRUE) [1]
        if (!is.null (dat)) {
            dat <- gsub (j [2], "", dat)
        }
        return (dat)
    })

    c (
        pkg = regex_data [1],
        version = regex_data [2]
    )
})
pkg_data <- do.call (rbind, pkg_data)

json_data <- data.frame (
    pkgname = pkg_data [, 1],
    submitted = json_input$author,
    iss_no = json_input$number,
    status = json_input$status,
    version = pkg_data [, 2],
    stats_version = json_input$stats_version
)
# Put most recent at top of file:
json_data <- json_data [order (json_data$iss_no, decreasing = TRUE), ]

jdir <- file.path ("pkgsvgs", "json")
if (!dir.exists (jdir)) {
    dir.create (jdir)
}
write_json (json_data, file.path (jdir, "onboarded.json"), pretty = TRUE, na = "null")
