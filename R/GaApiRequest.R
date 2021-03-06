#' @import httpuv
#' @importFrom jsonlite fromJSON toJSON
#' @importFrom httr GET POST PUT DELETE oauth_endpoints oauth1.0_token oauth2.0_token config
#'   stop_for_status content oauth_app modify_url add_headers
#' @importFrom R6 R6Class
#' @importFrom stringr str_c str_pad str_detect
#' @importFrom selectr querySelector querySelectorAll
#' @importFrom XML xmlParse xmlToList xmlApply
#' @importFrom plyr laply aaply
#' @importFrom stats runif
NULL

# This will be initialised using GoogleApiCreds() at time of package being loaded.
google_api <- new.env()

set_creds <- function(new_creds = list()) {
  assign("creds", new_creds, google_api)
}

set_creds()

get_creds <- function() {
  get("creds", google_api)
}

#' Google APIs OAuth 2.0 Credentials.
#'
#' Create a Google APIs OAuth2.0 credentials object
#'
#' @param userName Google username email address hint
#' @param appCreds Filename or named vector for client_id and client_secret.
#' @param cache httr OAuth2.0 cache
#' @param use_oob as per httr
#' @param appname prefix of environment variables that hold the client ID and client secret.
#'
#' @export
GoogleApiCreds <- function(
  userName = Sys.getenv(paste0(appname, "_USER")),
  appCreds = NULL,
  cache = character(0),
  use_oob = FALSE,
  appname = "GOOGLE_APIS"
){
  if (userName == "") {
    userName <- character(0)
  }
  cache_generic_file_name <- paste(tolower(appname), "auth.RDS", sep = "_")
  cache_file_prefix <- "."
  cache_default_dir <- "~" # Consider changing to tempdir() and/or make a global option (see httr options).
  if (length(cache) == 0) {
    if (length(userName) == 0) {
      cache <- cache_generic_file_name
    } else {
      cache <- paste0(userName, "_", cache_generic_file_name)
    }
    cache <- file.path(cache_default_dir, paste0(cache_file_prefix, cache))
  }
  creds <- list(
    app = app_oauth_creds(
      appname = appname,
      creds = appCreds
    ),
    user = list(
      login = userName,
      cache = cache
    ),
    use_oob = use_oob
  )
  set_creds(creds)
  creds
}

app_oauth_creds <- function(appname, creds = NULL) {
  if (typeof(creds) == "character" & length(creds) == 1L) {
    if (isTRUE(nchar(creds) > 0L)) {
      if (jsonlite::validate(creds)) {
        creds <- fromJSON(creds)
      } else if (file.exists(creds)) {
        creds <- fromJSON(creds)
      }
    } else {
      creds <- NULL
    }
    if ("installed" %in% names(creds)) {
      creds <- creds$installed
    }
  }
  if (typeof(creds) != "list") {
    if (length(creds) == 2 &
          identical(all(names(creds) %in% c("client_id", "client_secret")), TRUE)) {
      creds <- as.list(creds)
    } else {
      creds <- list(client_id = NULL, client_secret = NULL)
    }
  }
  if (is.null(creds$client_id)) {
    creds$client_id <- Sys.getenv(str_c(toupper(appname), "_CONSUMER_ID"))
    if (nchar(creds$client_id) == 0) {
      creds$client_id <- Sys.getenv("GANALYTICS_CONSUMER_ID")
      if (nchar(creds$client_id) > 0) {
        appname <- "GANALYTICS"
      } else {
        creds$client_id <- Sys.getenv("GA_CLIENT_ID")
      }
    }
  }
  if (is.null(creds$client_secret)) {
    creds$client_secret <- Sys.getenv(str_c(toupper(appname), "_CONSUMER_SECRET"))
    if (nchar(creds$client_secret) == 0) {
      creds$client_secret <- Sys.getenv("GANALYTICS_CONSUMER_SECRET")
      if (nchar(creds$client_secret) > 0) {
        appname <- "GANALYTICS"
      } else {
        creds$client_secret <- Sys.getenv("GA_CLIENT_SECRET")
      }
    }
  }
  if (!isTRUE(nchar(creds$client_id) > 0L | nchar(creds$client_secret) > 0L)) {
    creds <- dir(pattern = "^client_secret\\b\\.json$")[1]
    if (isTRUE(nchar(creds) > 0L)) {
      creds <- fromJSON(creds)
      if ("installed" %in% names(creds)) {
        creds <- creds$installed
      }
    } else {
      creds <- NULL
    }
  }
  oauth_app(
    appname = appname,
    key = creds$client_id,
    secret = creds$client_secret
  )
}

invisible(GoogleApiCreds())

# API Error response codes: https://developers.google.com/analytics/devguides/config/mgmt/v3/errors

#Make a Goolge API request
ga_api_request <- function(
  creds,
  request,
  scope = ga_scopes["read_only"],
  base_url = "https://www.googleapis.com/analytics/v3",
  req_type = "GET",
  body_list = NULL,
  fields = NULL,
  queries = NULL,
  max_results = NULL
) {
  stopifnot(scope %in% ga_scopes)
  google_api_request(
    creds = creds,
    scope = scope,
    request = request,
    base_url = base_url,
    queries = queries,
    req_type = req_type,
    body_list = body_list,
    fields = fields
  )
}

google_api_request <- function(creds, scope,
                               request, base_url,
                               queries = NULL, req_type = "GET",
                               body_list = NULL, fields = NULL,
                               max_results = NULL) {
  api_name <- "google"
  api_request(
    api_name = api_name,
    app = creds$app,
    base_url = paste(c(base_url, request), collapse = "/"),
    scope = scope,
    req_type = req_type,
    queries = c(
      queries,
      fields = parse_field_list(fields)
    ),
    body_list = body_list,
    user = creds$user,
    use_oob = creds$use_oob
  )
}

api_request <- function(api_name, app, base_url,
                        scope = NULL, req_type = "GET",
                        queries = NULL, body_list = NULL,
                        user = list(login = NA, cache = NA),
                        oauth_in_header = TRUE,
                        use_oob = FALSE,
                        oauth_version = "2.0") {
  req_type <- toupper(req_type)
  api_name <- tolower(api_name)
  stopifnot(
    req_type %in% c("GET", "POST", "PUT", "DELETE")
  )
  url <- form_url(base_url, queries)
  endpoint <- oauth_endpoints(name = api_name)
  if (length(user$login) != 1) {user$login <- NA}
  if (!is.na(user$login)) {
    endpoint$authorize <- modify_url(
      endpoint$authorize,
      query = list(login_hint = user$login)
    )
  }
  scope <- if (!is.null(scope)) {
    paste(scope, collapse = " ")
  }
  switch(
    oauth_version,
    `1.0` = {
      token <- oauth1.0_token(
        endpoint = endpoint,
        app = app,
        permission = scope,
        cache = user$cache
      )
    },
    `2.0` = {
      token <- oauth2.0_token(
        endpoint = endpoint,
        app = app,
        scope = scope,
        use_oob = use_oob,
        as_header = oauth_in_header,
        cache = user$cache
      )
    }
  )
  args <- list(
    url = url,
    config = config(token = token)
  )
  if (!is.null(body_list)) {
    body <- toJSON(
      body_list,
      pretty = TRUE#, asIs = TRUE #, auto_unbox = TRUE
    )
    args$config <- c(
      args$config,
      add_headers(
        `Content-Type` = "application/json"
      )
    )
    args <- c(args, list(body = body))
  }

  attempts <- 0
  succeeded <- FALSE
  while (attempts <= 5 & !succeeded) {
    attempts <- attempts + 1
    response <- do.call(req_type, args)
    json_content <- response_to_list(response)
    if (any(json_content$error$errors$reason %in% c('userRateLimitExceeded', 'quotaExceeded'))) {
      Sys.sleep((2 ^ attempts) + runif(n = 1, min = 0, max = 1))
    } else {
      message(json_content$error$message)
      stop_for_status(response)
      succeeded <- TRUE
    }
  }
  json_content
}

form_url <- function(base_url, queries = NULL) {
  paste(
    c(
      base_url,
      if (length(queries) >= 1) {
        paste(
          aaply(seq_along(queries), 1, function(query_index){
            query <- queries[query_index]
            paste(names(queries)[query_index], URLencode(as.character(query), reserved = TRUE), sep = "=")
          }),
          collapse = "&"
        )
      }
    ),
    collapse = "?"
  )
}

response_to_list <- function(response) {
  content_type <- response$headers$`content-type`
  if (length(content(response)) >= 1) {
    response_text <- content(x = response, as = "text")
    if (str_detect(content_type, "^application/json;")) {
      return(fromJSON(response_text))
    } else if (str_detect(content_type, "^application/atom\\+xml;")) {
      xml_doc <- xmlParse(response_text, asText = TRUE)
      feed <- querySelectorAll(doc = xml_doc, selector = "x|feed", ns = "x")
      ret_list <- lapply(feed, function(feed_node){
        xmlApply(feed_node, function(node){
          xmlToList(node)
        })
      })
      ret_list <- ret_list[[1]]
      ret_list <- c(
        ret_list[names(ret_list) != "entry"],
        entries = list(
          ret_list[names(ret_list) == "entry"]
        )
      )
      return(ret_list)
    }
  }
  return(response)
}

# This function accepts a recursive list of list elements, each named to represent a field,
# and converts this into a field
# e.g.
# field_list <- list(
#   "a" = list(),
#   "b" = list(
#     "*" = list(
#       "f" = list(),
#       "z" = list()
#     ),
#     "c" = list(),
#     "d" = list()
#   ),
#   "e" = list()
# )
parse_field_list <- function(field_list) {
  # A list must be provided, and as this function is recursive,
  # all elements within that list must also be lists, and so on.
  if (length(field_list) == 0) {
    return(NULL)
  }
  stopifnot(
    is.list(field_list)
  )
  # for each element within the list...
  fields <- laply(seq_along(field_list), function(field_index) {
    # Get the name and content of the field element
    field_name <- names(field_list)[field_index]
    field_content <- field_list[[field_index]]
    # Get the legnth of the field's content
    field_length <- length(field_content)
    # if that element is a end node then
    if (field_length == 0) {
      # return the name of that node
      return(field_name)
    } else {
      # otherwise recursively parse each of its sub elements
      sub_fields <- parse_field_list(field_content)
      # if there was more than one sub element, then group those sub elements
      if (field_length > 1) {
        sub_fields <- paste0("(", sub_fields, ")")
      }
      # the sub fields are returned with a preceding "/"
      return(paste0(
        field_name, "/", sub_fields
      ))
    }
  })
  # each of the fields must be separated by ","
  parsed_fields <- paste0(fields, collapse = ",")
  return(parsed_fields)
}
