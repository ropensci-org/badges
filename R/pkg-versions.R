# Get submitted and approved versions of packages
#
# ---------------------------------------------

# First get timestamps of all issue labels, to use the first one to identify
# initial commit, and the final "approved" label to identify final commit.

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
                                   createdAt
                                   body
                                   timelineItems (itemTypes: LABELED_EVENT, first: 100) {
                                       nodes {
                                           ... on LabeledEvent {
                                               actor {
                                                   login
                                               },
                                               createdAt,
                                               label {
                                                   name
                                               }
                                           }
                                       }
                                   }
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

number <- created_at <- body <- NULL
label_data <- list ()

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
    created_at <- c ( # nolint
        created_at,
        vapply (edges, function (i) i$node$createdAt, character (1L))
    )
    body <- c (
        body,
        vapply (edges, function (i) i$node$body, character (1L))
    )

    label_data <- c (
        label_data,
        lapply (edges, function (i) {
            lapply (i$node$timelineItems$nodes, function (j) {
                c (j$label$name, j$createdAt)
            })
        })
    )
}

# ---------------------------------------------
#
# Then get 'onboarded.json' and reduce issues down to only onboarded packages:

u <- paste0 (
    "https://raw.githubusercontent.com/ropensci-org/badges/",
    "gh-pages/json/onboarded.json"
)
f <- tempfile (fileext = ".json")
download.file (u, f, quiet = TRUE)

dat <- jsonlite::read_json (f, simplify = TRUE)
i <- which (dat$status == "reviewed")
index <- which (number %in% dat$iss_no [i])

number <- number [index]
created_at <- created_at [index]
label_data <- label_data [index]
body <- body [index]

# ---------------------------------------------
#
# Set up query to get all commit data for specified repo
get_commits_qry <- function (org = "ropensci",
                             repo = pkg,
                             end_cursor = NULL) {

    after_txt <- ""
    if (!is.null (end_cursor)) {
        after_txt <- paste0 (", after:\"", end_cursor, "\"")
    }

    q <- paste0 ("{
        repository(owner:\"", org, "\", name:\"", repo, "\") {
            ... on Repository{
                defaultBranchRef{
                    target{
                        ... on Commit{
                            history(first:100", after_txt, "){
                                pageInfo {
                                    hasNextPage
                                    endCursor
                                }
                                edges{
                                    node{
                                        ... on Commit{
                                            committedDate
                                            oid
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }")

    return (q)
}


# ---------------------------------------------
#
# Finally, get initial and final versions of each package, starting with fn to
# download 'DESC' file for a specified date, and to extract the corresponding
# version.

get_desc_version <- function (pkg, commit_data, t0, org = "ropensci") {

    ret <- NA_character_

    t0 <- lubridate::ymd_hms (t0)
    oid <- commit_data$oid [max (which (commit_data$date <= t0))]
    url_base <- paste0 (
        "https://raw.githubusercontent.com/",
        org, "/", pkg, "/"
    )
    u <- paste0 (url_base, oid, "/", "DESCRIPTION")
    f <- tempfile (pattern = "DESCRIPTION")
    chk <- tryCatch (
        error =  function (e) NULL,
        suppressWarnings (
            download.file (u, f, quiet = TRUE)
        )
    )
    if (is.null (chk)) {
        return (ret)
    }
    if (chk != 0) {
        return (ret)
    }

    d <- tryCatch (
        read.dcf (f),
        error = function (e) NULL
    )
    if (!is.null (d)) {
        v <- d [1, grep ("[Vv]ersion", colnames (d))]
    } else {
        d <- readLines (f)
        ptn <- "^[Vv]ersion\\:(\\s?)"
        v <- gsub (ptn, "", grep (ptn, d, value = TRUE))
    }
    chk <- file.remove (f)
    return (unname (v))
}

pkg_versions <- lapply (seq_along (number), function (i) {

    # Get 'Version' stated on submission issue:
    body_i <- strsplit (body [[i]], "\n") [[1]]
    v <- grep ("^[Vv]ersion\\:", body_i, value = TRUE) [1]
    if (!is.null (v)) {
        v <- gsub ("^[Vv]ersion\\:(\\s)|\\r|", "", v)
    }
    pkg <- dat$pkgname [dat$iss_no == number [i]]
    v0 <- v1 <- NA_character_

    if (is.na (pkg)) {
        return (c (stated = v, start = v0, end = v1))
    }

    ld <- do.call (rbind, label_data [[i]])
    label_indices <- regmatches (ld [, 1], gregexpr ("^[0-9]\\/", ld [, 1]))
    index <- which (vapply (label_indices, length, integer (1L)) == 0L)
    if (length (index) > 0L) {
        label_indices [index] <- NA_character_
    }
    label_indices <- as.integer (gsub ("\\/$", "", label_indices))

    # Get commit history of that repo:
    has_next_page <- TRUE
    end_cursor <- NULL

    commit_data <- list ()

    org <- "ropensci"
    valid_url <- function (org, pkg, t = 2) {
        con <- url (paste0 ("https://github.com/", org, "/", pkg))
        check <- suppressWarnings (try (
            open.connection (con, open = "rt", timeout = t), silent = TRUE) [1])
        suppressWarnings (try (close.connection (con), silent = TRUE))
        ifelse (is.null (check), TRUE, FALSE)
    }
    if (!valid_url (org, pkg)) {
        org <- "ropensci-archive"
    }
    if (!valid_url (org, pkg)) {
        return (c (stated = v, start = v0, end = v1))
    }

    while (has_next_page) {

        q <- get_commits_qry (
            org = org,
            repo = pkg,
            end_cursor = end_cursor
        )
        dat <- gh::gh_gql (query = q)

        history <- dat$data$repository$defaultBranchRef$target$history
        has_next_page <- history$pageInfo$hasNextPage
        end_cursor <- history$pageInfo$endCursor

        edges <- dat$data$repository$defaultBranchRef$target$history$edges

        commit_data <- c (
            commit_data,
            lapply (edges, function (i) {
                c (i$node$oid, i$node$committedDate)
            })
        )
    }
    commit_data <- data.frame (do.call (rbind, commit_data))
    names (commit_data) <- c ("oid", "date")
    commit_data$date <- lubridate::ymd_hms (commit_data$date)

    if (min (label_indices, na.rm = TRUE) < 3) {
        t0 <- lubridate::ymd_hms (ld [which.min (label_indices), 2])
        v0 <- get_desc_version (pkg, commit_data, t0)
    }

    if (max (label_indices, na.rm = TRUE) == 6) {
        t1 <- lubridate::ymd_hms (ld [which.max (label_indices), 2])
        v1 <- get_desc_version (pkg, commit_data, t1)
    }

    c (stated = v, start = v0, end = v1)
})

pkg_versions <- data.frame (do.call (rbind, pkg_versions))
