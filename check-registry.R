#!/usr/bin/env Rscript

# Script to check "onboarded.json" made by "update_badges.R" against the
# rOpenSci registry, to ensure package names are consistent.
# https://github.com/ropensci-org/badges/issues/20

ob <- file.path ("pkgsvgs", "json", "onboarded.json")
if (!file.exists (ob)) {
    stop ("onboarded.json not found")
}
json_data <- jsonlite::read_json (ob, simplifyVector = TRUE)
json_data <- json_data [json_data$status == "reviewed", ] |>
    dplyr::rename (package_onboarded = pkgname)

u <- "https://ropensci.r-universe.dev/api/packages/"
pj <- jsonlite::read_json (u, simplifyVector = TRUE)
meta <- pj$`_metadata`
index <- which (!is.na (meta$review$id))
pj_dat <- data.frame (
    package_current = pj$Package,
    url = pj$`_devurl`,
    iss_no = meta$review$id,
    status = meta$review$status,
    review_url = meta$review$url
) [index, ]
pj_dat <- dplyr::left_join (pj_dat, json_data, by = "iss_no")

# At that point, "pj_dat" has "package_current" as the actual package DESC name
# taken from packages.json, and "package_onboarded" as the name taken from
# "onboarded.json" which is written in the "update_badges.R" script, and
# ultimately taken from the template at the top of the GitHub review issues.
#
# Mismatches may occur because either:
# 1. One review yielded muliple packages (e.g., targets, babette), or
# 2. Issue title and package name are actually mismatched.
#
# We need to ignore the first, and identify only the second casese.

index <- which (pj_dat$package != pj_dat$pkgname)
if (length (index) > 0) {
    mismatch_issues <- sort (unique (pj_dat$iss_no [index]))
    pj_dat_mismatch <- pj_dat [which (pj_dat$iss_no %in% mismatch_issues), ]
    # Truly mmimatched issues will then only have a single "iss_no" value in
    # that table:
    mismatch_issues <- table (pj_dat_mismatch$iss_no)
    mismatch_issues <- as.integer (names (mismatch_issues) [which (mismatch_issues == 1L)])
    index <- which (pj_dat$iss_no %in% mismatch_issues)
}

if (length (index) > 0) {

    pj_mismatch <- pj_dat [index, ]
    hrefs <- paste0 (
        " - [ ] https://github.com/ropensci/software-review/issues/",
        pj_mismatch$iss_no,
        "  '", pj_mismatch$package_current, "' in roregistry;  '",
        pj_mismatch$package_onboarded, "' in review thread"
    )
    iss_msg <- paste0 (
        "The following software review issue",
        ifelse (length (index) > 1, "s", ""),
        " have package names which do not match those in the registry:"
    )
    iss_end_comment <- paste0 (
        "\nTo fix, update the values in the review threads to reflect ",
        "actual package names in the registry. The review thread ",
        "values come from the YAML template where present, or else the ",
        "'Package' value in the full DESCRIPTION text. Update one or both ",
        "of these to fix. Issue titles may be left in whatever form ",
        "they currently are."
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
