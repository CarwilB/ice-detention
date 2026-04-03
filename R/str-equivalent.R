#' String Comparison That Ignores Certain Factors
#'
#' This function compares two strings while ignoring case, accents, leading/trailing whitespace,
#' non-breaking spaces, and double quotes. It performs a normalized comparison to determine equivalence.
#'
#' @param x A character vector or string to compare.
#' @param y A character vector or string to compare.
#'
#' @return A logical vector indicating whether the strings are equivalent.
#'
#' @details
#' The function performs the following transformations before comparison:
#' \itemize{
#'   \item Trims leading and trailing whitespace using \code{\link[base]{trimws}}.
#'   \item Replaces non-breaking spaces (`\u00a0`) with regular spaces (` `).
#'   \item Removes accents using \code{\link[stringi]{stri_trans_general}} with the "Latin-ASCII" transformation.
#'   \item Removes double quotes (`"`).
#'   \item Performs a case-insensitive comparison using \code{\link[stringr]{str_equal}}.
#' }
#'
#' @examples
#' str_equivalent("  Café", "cafe") # TRUE
#' str_equivalent("Hello\u00a0World", "hello world") # TRUE
#' str_equivalent("Quote\"", "quote") # TRUE
#' str_equivalent("Case", "case") # TRUE
#' str_equivalent("Mismatch", "mismatch!") # FALSE
#'
#' @importFrom stringr str_replace_all str_equal
#' @importFrom stringi stri_trans_general
#' @export
str_equivalent <- function(x, y) {
  x <- trimws(x) # trim whitespace
  y <- trimws(y)
  
  x <- stringr::str_replace_all(x, "\u00a0", " ") # replace non-breaking space
  y <- stringr::str_replace_all(y, "\u00a0", " ")
  
  x <- stringi::stri_trans_general(x, "Latin-ASCII") # eliminate accents
  y <- stringi::stri_trans_general(y, "Latin-ASCII")
  
  x <- str_replace_all(x, "\u0022", "") # remove double quotes
  y <- str_replace_all(y, "\u0022", "")
  
  stringr::str_equal(x, y, ignore_case = TRUE)
}

#' Find Indices of Equivalent Strings
#'
#' This function finds the indices of strings in a list that are equivalent to the target string, 
#' considering case insensitivity, accent removal, whitespace trimming, and non-breaking space replacement.
#'
#' @param string A character string to compare.
#' @param list A character vector against which equivalence is checked.
#'
#' @return An integer vector of indices where the string is equivalent to elements in the list.
#'
#' @details
#' The function uses \code{\link{str_equivalent}} to determine string equivalence. 
#' It returns the indices of all matches in the list.
#'
#' @examples
#' equivalent_which("café", c("cafe", "tea", "coffee")) # Returns 1
#' equivalent_which("hello", c("Hello", "world"))       # Returns 1
#' 
#' @seealso \code{\link{str_equivalent}}
#' @export
equivalent_which <- function(string, list){
  which(str_equivalent(string, list))
}

#' Find Equivalent String in a List
#'
#' This function finds the first string in a list that is equivalent to the target string, 
#' considering case insensitivity, accent removal, whitespace trimming, and non-breaking space replacement.
#'
#' @param string A character string to compare.
#' @param list A character vector against which equivalence is checked.
#'
#' @return The first matching string from the list, or \code{NA} if no equivalent string is found.
#'
#' @details
#' The function uses \code{\link{str_equivalent}} to determine string equivalence. 
#' If no match is found, it returns \code{NA}.
#'
#' @examples
#' equivalent_match("café", c("cafe", "tea", "coffee")) # Returns "cafe"
#' equivalent_match("hello", c("Hello", "world"))       # Returns "Hello"
#' equivalent_match("bye", c("Hello", "world"))         # Returns NA
#'
#' @seealso \code{\link{str_equivalent}}, \code{\link{equivalent_which}}
#' @export
equivalent_match <- function(string, list){
  if (length(equivalent_which(string,list)) == 0) 
    return(NA)
  list[which(str_equivalent(string, list))]
}

#' Check for Equivalent Strings in a List
#'
#' This function checks if any string in a list is equivalent to a target string, 
#' considering case insensitivity, accent removal, whitespace trimming, and non-breaking space replacement.
#'
#' @param string A character string to compare.
#' @param string_list A character vector of potential matches.
#'
#' @return A logical value: \code{TRUE} if any string in the list is equivalent to the target string, 
#' or \code{FALSE} otherwise.
#'
#' @details
#' The function uses \code{\link{str_equivalent}} to determine string equivalence and applies it 
#' to each element of the list.
#'
#' @examples
#' str_equivalent_list("café", c("cafe", "tea", "coffee")) # Returns TRUE
#' str_equivalent_list("hello", c("world", "hi"))          # Returns FALSE
#'
#' @seealso \code{\link{str_equivalent}}
#' @export
str_equivalent_list <- function(string, string_list) {
  # Check if any member of string_list is equivalent to string using str_equivalent
  any(sapply(string_list, function(x) str_equivalent(string, x)))
}

#' Normalize a String for Join Keys
#'
#' Applies the same transformations as \code{\link{str_equivalent}} and returns
#' the normalized string. Useful for creating case-insensitive join keys in
#' \code{dplyr::left_join()} and similar operations.
#'
#' @param x A character vector to normalize.
#' @return A character vector of normalized (lowercased, accent-stripped,
#'   whitespace-trimmed) strings.
#'
#' @examples
#' normalize_join_key("CBP Chula Vista BPS")
#' # "cbp chula vista bps"
#' normalize_join_key("  Café  ")
#' # "cafe"
#'
#' @seealso \code{\link{str_equivalent}}
#' @export
normalize_join_key <- function(x) {
  x <- trimws(x)
  x <- stringr::str_replace_all(x, "\u00a0", " ")
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- stringr::str_replace_all(x, "\u0022", "")
  tolower(x)
}
