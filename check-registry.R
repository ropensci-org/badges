#!/usr/bin/env Rscript

# Script to check "onboarded.json" made by "update_badges.R" against the
# rOpenSci registry, to ensure package names are consistent.
# https://github.com/ropensci-org/badges/issues/20

ob <- file.path ("pkgsvgs", "json", "onboarded.json")
if (!file.exists (ob)) {
    stop ("onboarded.json not found")
}
json_data <- jsonlite::read_json (ob, simplifyVector = TRUE)
json_data <- json_data [json_data$status == "reviewed", ]

u_base <- "https://api.github.com/repos/ropensci/roregistry/"
u <- paste0 (u_base, "contents/packages.json")
ftmp <- tempfile (fileext = ".json")
pj <- gh::gh (
    u,
    .accept = "application/vnd.github.raw+json",
    .destfile = ftmp
)
pj <- jsonlite::read_json (ftmp, simplifyVector = TRUE)
file.remove (ftmp)

# Check against codemeta created in 'makeregistry', which extracts actual
# current package names:
cm_url <- "https://github.com/ropensci/roregistry/blob/gh-pages/raw_cm.json?raw=true"
cm <- jsonlite::read_json (cm_url)
cm <- cm[lengths(cm) > 0]
keep <- c ("identifier", "name", "codeRepository")
cm <- lapply (cm, function (i) {
    revdat <- ifelse (length (i$review) > 0L, i$review$url, NA_character_)
    data.frame (c (i [keep], review = revdat))
})
cm <- do.call (rbind, cm)

cm_pj <- dplyr::left_join (pj, cm, by = c ("url" = "codeRepository"))

index <- which (!is.na (cm_pj$review) & is.na (cm_pj$metadata$review$id))
# packages.json has metadata consisting of:
# - review$id
# - review$status
# - review$version
# - review$organization
# - review$url

ids <- regmatches (
    cm_pj$review [index],
    regexpr ("\\/[0-9]+$", cm_pj$review [index])
)
ids <- as.integer (gsub ("^\\/", "", ids))
cm_pj$metadata$review$id [index] <- ids
cm_pj$metadata$review$url [index] <- cm_pj$review [index]

# The `json_data` include packages which have been archived on GitHub.
# These no longer appear at all in packages.json, so reduce `pj` data down to
# only those in the registry:
pj_reg <- cm_pj [which (!is.na (cm_pj$metadata$review$id)), ]
pj_reg <- data.frame (
    package_pj = pj_reg$package,
    status = pj_reg$metadata$review$status,
    iss_no = pj_reg$metadata$review$id
)
pj_reg <- pj_reg [which (pj_reg$iss_no %in% json_data$iss_no), ]
index <- match (pj_reg$iss_no, json_data$iss_no)
pj_reg$pkgname <- json_data$pkgname [index]

# At that point, "package_pj" is the actual package DESC name taken from
# packages.json, and "pkgname" is from "onboarded.json" here, written here in
# the "update_badges.R" script, and take from GitHub issue titles.
#
# Mismatches may occur because either:
# 1. One review yielded muliple packages (e.g., targets, babette), or
# 2. Issue title and package name are actually mismatched.
#
# We need to ignore the first, and identify only the second casese.

index <- which (pj_reg$pkgname != pj_reg$package_pj)
if (length (index) > 0) {
    mismatch_issues <- sort (unique (pj_reg$iss_no [index]))
    pj_reg_mismatch <- pj_reg [which (pj_reg$iss_no %in% mismatch_issues), ]
    # Truly mmimatches issues will then only have a single "iss_no" value in
    # that table:
    mismatch_issues <- table (pj_reg_mismatch$iss_no)
    mismatch_issues <- as.integer (names (mismatch_issues) [which (mismatch_issues == 1L)])
    index <- which (pj_reg$iss_no %in% mismatch_issues)
}

if (length (index) > 0) {

    pj_mismatch <- pj_reg [index, ]
    hrefs <- paste0 (
        " - [ ] https://github.com/ropensci/software-review/issues/",
        pj_mismatch$iss_no,
        "  '", pj_mismatch$package_pj, "' in roregistry;  '",
        pj_mismatch$pkgname, "' in review thread"
    )
    iss_msg <- paste0 (
        "The following software review issue",
        ifelse (length (index) > 1, "s", ""),
        " have package names which do not match those in the registry:"
    )
    iss_end_comment <- paste0 (
        "\nTo fix, update the values in the review threads to reflect ",
        "actual package names in the registry. The review thread ",
        "values come from the YAML template; issue titles may be ",
        "left in whatever form they currently are."
    )
    iss_msg <-
        paste0 (c (iss_msg, hrefs, iss_end_comment), collapse = "\n")

    cmd <- paste (
        "gh issue comment 24 ",
        "--repo ropensci-org/badges",
        paste0 ("--body '", iss_msg, "'")
    )
    system (cmd)
}
