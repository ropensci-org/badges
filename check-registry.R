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

# The `json_data` include packages which have been archived on GitHub.
# These no longer appear at all in packages.json, so reduce `pj` data down to
# only those in the registry:
pj_reg <- pj [which (!is.na (pj$metadata$review$id)), ]
pj_reg <- data.frame (
    package_pj = pj_reg$package,
    status = pj_reg$metadata$review$status,
    iss_no = pj_reg$metadata$review$id
)
pj_reg <- pj_reg [which (pj_reg$iss_no %in% json_data$iss_no), ]
index <- match (pj_reg$iss_no, json_data$iss_no)
pj_reg$pkgname <- json_data$pkgname [index]

index <- which (pj_reg$pkgname != pj_reg$package_pj)

if (length (index) > 0) {

    pj_mismatch <- pj_reg [index, ]
    hrefs <- paste0 (
        " - https://github.com/ropensci/software_review/issues/",
        pj_mismatch$iss_no,
        "  '", pj_mismatch$package_pj, "' in roregistry;  '",
        pj_mismatch$pkgname, "' in review thread/here"
    )
    iss_msg <- paste0 (
        "The following software review issue",
        ifelse (length (index) > 1, "s", ""),
        " have package names which do not match those in the registry:"
    )
    iss_msg <- paste0 (c (iss_msg, hrefs), collapse = "\n")

    cmd <- paste (
        "gh issue create ",
        "--repo ropensci-org/badges",
        "--title 'repository name mismatch'",
        "--label 'bug'",
        paste0 ("--body '", iss_msg, "'")
    )
    system (cmd)
}
