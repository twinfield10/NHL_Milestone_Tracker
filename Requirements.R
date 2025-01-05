# Requirements.R

library(tidyverse)
library(ggplot2)

get_schedule <- function(season){
  
  # Set Start/End Dates for url
  if(season == 2020){
    start_date <- "2019-09-01"
    end_date <- "2020-09-30"
  } else {
    start_date <- glue::glue("{season-1}-09-01")
    end_date <- glue::glue("{season}-07-31")
  }
  
  start_date <- as.Date(start_date, "%Y-%m-%d")
  end_date <- as.Date(end_date, "%Y-%m-%d")
  
  # Start URL
  url <- glue::glue("https://api-web.nhle.com/v1/schedule/{start_date}")
  site <- jsonlite::read_json(url)
  
  # Get Start and End
  regSeasonStart = site$regularSeasonStartDate
  regSeasonEnd = site$regularSeasonEndDate
  
  print(regSeasonStart)
  print(regSeasonEnd)
    
  season_dates <- seq.Date(
    from = as.Date(regSeasonStart , "%Y-%m-%d"),
    to = as.Date(regSeasonEnd , "%Y-%m-%d"),
    by = "day"
  )
  
  # Build DataFrame
  url_sched = glue::glue("https://api-web.nhle.com/v1/schedule/{regSeasonStart}")
  df1 <- jsonlite::fromJSON(url_sched) %>%
    as.data.frame()
  
  # Expand Raw DF
  df2 <- df1 %>%
    select(-gameWeek.datePromo) %>%
    unnest(gameWeek.games) %>%
    select(-c(tvBroadcasts)) %>%
    unnest_wider(venue) %>%
    unnest_wider(awayTeam) %>%
    unnest_wider(homeTeam)
    
  
  # Next Date
  next_date <- df2$nextStartDate[1]
  
  print(df2)
  return(df2)
  
  
  
}
schedule <- get_schedule(2024)

schedule$venue

print(names(schedule))

nhl_schedule <- function(season = NULL,
                         day = as.Date(Sys.Date(), "%Y-%m-%d")){
  
  if(is.null(season)){
    # scrape day's games
    url <- glue::glue("https://api-web.nhle.com/v1/schedule/{day}")
    
    site <- jsonlite::read_json(url)
    
    if(site$totalGames == 0){
      message(glue::glue("No NHL games found on {day}"))
    }
    
  } else {
    # scrape season's games
    if(season == 2020){
      # searching the nhl api for games between Sep 1 2019 & Sep 30th 2020
      url <- glue::glue("https://statsapi.web.nhl.com/api/v1/schedule?startDate={season-1}-09-01&endDate={season}-09-30")
    } else {
      # searching the nhl api for games between Sep 1 & July 31
      url <- glue::glue("https://api-web.nhle.com/v1/schedule/{day}")
    }
    
    site <- jsonlite::read_json(url)
  }
  
  
  games <- jsonlite::fromJSON(jsonlite::toJSON(site[["dates"]]), flatten=TRUE) %>%
    dplyr::tibble()
  game_dates <- data.table::rbindlist(games$games, fill = TRUE)
  game_dates <- game_dates %>%
    janitor::clean_names()
  select_cols <- as.vector(colnames(game_dates)[!stringr::str_detect(colnames(game_dates),"league(.*)")])
  game_dates <- game_dates %>%
    dplyr::select(dplyr::all_of(select_cols))
  colnames(game_dates) <- gsub("teams_","",colnames(game_dates))
  game_dates <- game_dates %>%
    dplyr::rename(
      "game_id" = "game_pk",
      "season_full" = "season",
      "game_type_abbreviation" = "game_type",
      "game_date_time" = "game_date") %>%
    dplyr::mutate(
      game_type = dplyr::case_when(
        substr(.data$game_id, 6, 6) == 1 ~ "PRE",
        substr(.data$game_id, 6, 6) == 2 ~ "REG",
        substr(.data$game_id, 6, 6) == 3 ~ "POST",
        substr(.data$game_id, 6, 6) == 4 ~ "ALLSTAR"),
      venue_id = ifelse(.data$venue_id == "NULL", NA_integer_, .data$venue_id),
      game_date = as.Date(substr(.data$game_date_time,1,10),"%Y-%m-%d"))
  
  game_dates <- game_dates %>%
    dplyr::filter(.data$game_type == "REG" | .data$game_type == "POST") %>%
    make_fastRhockey_data("NHL Schedule Information from NHL.com",Sys.time())
  
  # make sure we're only pulling for correct season by using
  # the season code in the game_id
  
  if(!is.null(season)) {
    game_dates <- game_dates %>%
      dplyr::filter(substr(.data$game_id, 1, 4) == (as.numeric(season) - 1))
  }
  game_dates <- tidyr::unnest(game_dates,
                              cols = c("game_id", "link", "game_type_abbreviation", "season_full",
                                       "game_date_time", "status_abstract_game_state",
                                       "status_coded_game_state", "status_detailed_state",
                                       "status_status_code", "status_start_time_tbd", "away_score",
                                       "away_team_id", "away_team_name", "away_team_link",
                                       "home_score", "home_team_id", "home_team_name",
                                       "home_team_link", "venue_name", "venue_link", "venue_id",
                                       "content_link"))
  
  return(game_dates)
}