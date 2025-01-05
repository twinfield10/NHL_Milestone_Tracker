import pandas as pd
import numpy as np
import polars as pl
import requests
import json
from typing import Any, Dict, List
from datetime import datetime, date, timedelta

class LoadData:
    def __init__(self, year:int):
        """
        Initialize the LoadData class with NHL API URL.
        
        """
        self.api_base = "https://api-web.nhle.com/v1/"
        self.year = year
        self.season_dates = None
    
    def get_date_dict(self):
        """
        Set up a dictionary containing all dates for the season:
        - Season ID (i.e., 20242025)
        - Pre-Season Start Date
        - Pre-Season End Date
        - Regular Season Start Date
        - Regular Season End Date
        - Post-Season Start Date
        - Post-Season End Date
        """
        # Initialize
        if self.year == 2020:
            start_date = f"{self.year-1}-09-01"
            end_date = f"{self.year}-09-30"
        else:
            start_date = f"{self.year-1}-09-01"
            end_date = f"{self.year-1}-07-31"

        # Load Season Data
        raw = requests.get(f"{self.api_base}schedule/{start_date}")
        raw = raw.json()

        self.season_dates = {
            "seasonId": f"{self.year-1}{self.year}",
            "preSeason_Start": datetime.strptime(raw.get("preSeasonStartDate"), "%Y-%m-%d").date(),
            "preSeason_End": datetime.strptime(raw.get("regularSeasonStartDate"), "%Y-%m-%d").date() - timedelta(days=1),
            "regSeason_Start": datetime.strptime(raw.get("regularSeasonStartDate"), "%Y-%m-%d").date(),
            "regSeason_End": datetime.strptime(raw.get("regularSeasonEndDate"), "%Y-%m-%d").date(),
            "postSeason_Start": datetime.strptime(raw.get("regularSeasonEndDate"), "%Y-%m-%d").date() + timedelta(days=1),
            "postSeason_End": datetime.strptime(raw.get("playoffEndDate"), "%Y-%m-%d").date()
        }

        for key, value in self.season_dates.items():
            if isinstance(value, date):
                self.season_dates[key] = value.strftime("%Y-%m-%d")
    
    def get_schedules(self):
        """
        Return a dataframe of NHL Schedules given a season
        
        """
        # Initialize Start Date + JSON
        self.get_date_dict()
        start = self.season_dates['regSeason_Start']
        all_schedules = pd.DataFrame()

        while True:
            # Load JSON from API
            raw = requests.get(f"{self.api_base}schedule/{start}")
            data = raw.json()

            # Parse main DataFrame
            df = pd.json_normalize(data)
            game_df = pd.json_normalize(df['gameWeek'].explode().dropna())
            detail_df = pd.json_normalize(game_df['games'].explode().dropna())

            # Clean-Up
            try:
                df = df[['nextStartDate', 'previousStartDate']]
                next_start_date = df[['nextStartDate']].iloc[0].item()
                next_start_datetime = datetime.strptime(next_start_date, "%Y-%m-%d").date()
            except:
                break

            # Check if we have exceeded the regular season end date
            reg_season_end = datetime.strptime(self.season_dates['postSeason_End'], "%Y-%m-%d").date()
            if next_start_datetime > reg_season_end:
                break

            start = next_start_date

            # Prepare game data
            game_df = game_df[['date', 'dayAbbrev', 'numberOfGames']]
            date_df = game_df.loc[np.repeat(game_df.index, game_df['numberOfGames'])]
            date_df = date_df.reset_index(drop=True)

            # Select relevant game details
            sel_detail = ['id', 'season', 'gameType', 'neutralSite', 'startTimeUTC',
                          'easternUTCOffset', 'venueUTCOffset', 'venueTimezone', 'gameState',
                          'gameScheduleState', 'venue.default',
                          'awayTeam.id', 'awayTeam.commonName.default',
                          'awayTeam.placeName.default', 'awayTeam.placeNameWithPreposition.default',
                          'awayTeam.abbrev', 'awayTeam.logo', 'awayTeam.darkLogo', 'awayTeam.awaySplitSquad',
                          'homeTeam.id', 'homeTeam.commonName.default',
                          'homeTeam.placeName.default', 'homeTeam.placeNameWithPreposition.default',
                          'homeTeam.abbrev', 'homeTeam.logo', 'homeTeam.darkLogo', 'homeTeam.homeSplitSquad',
                          'periodDescriptor.maxRegulationPeriods']
            detail_df = detail_df[sel_detail]
            detail_df = detail_df.reset_index(drop=True)

            # Combine the date and detail dataframes
            final = pd.concat([date_df, detail_df], axis=1)

            # Append to the cumulative dataframe
            all_schedules = pd.concat([all_schedules, final], ignore_index=True)

        return all_schedules
    
